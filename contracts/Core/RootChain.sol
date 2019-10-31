// Copyright Loom Network 2018 - All rights reserved, Dual licensed on GPLV3
// Learn more about Loom DappChains at https://loomx.io
// All derivitive works of this code must incluse this copyright header on every file

pragma solidity ^0.5.2;

// ERC721
import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721Receiver.sol";

// Lib deps
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../Libraries/Transaction/Transaction.sol";
import "../Libraries/ECVerify.sol";
import "../Libraries/ChallengeLib.sol";

// SMT and VMC
import "./SparseMerkleTree.sol";
import "./ValidatorManagerContract.sol";


contract RootChain is IERC721Receiver {

    event Debug(address message);

    /**
     * Event for coin deposit logging.
     * @notice The Deposit event indicates that a deposit block has been added
     *         to the Plasma chain
     * @param slot Plasma slot, a unique identifier, assigned to the deposit
     * @param blockNumber The index of the block in which a deposit transaction
     *                    is included
     * @param from The address of the depositor
     * @param contractAddress The address of the contract making the deposit
     */
    event Deposit(uint64 indexed slot, uint256 blockNumber,
        address indexed from, address indexed contractAddress);

    /**
     * Event for block submission logging
     * @notice The event indicates the addition of a new Plasma block
     * @param blockNumber The block number of the submitted block
     * @param root The root hash of the Merkle tree containing all of a block's
     *             transactions.
     * @param timestamp The time when a block was added to the Plasma chain
     */
    event SubmittedBlock(uint256 blockNumber, bytes32 root, uint256 timestamp);

    /**
     * Event for secret-revealing block submission logging
     * @notice The event indicates the addition of a new Secret Revealing block
     * @param blockNumber The block number of the submitted block
     * @param root The root hash of the Merkle tree containing all of a block's
     *             secrets.
     * @param timestamp The time when a block was added to the Plasma chain
     */
    event SubmittedSecretBlock(uint256 blockNumber, bytes32 root, uint256 timestamp);

    /**
     * Event for logging exit starts
     * @param slot The slot of the coin being exited
     * @param owner The user who claims to own the coin being exited
     */
    event StartedExit(uint64 indexed slot, address indexed owner);

    /**
     * Event for exit challenge logging
     * @notice This event only fires if `challengeBefore` is called.
     * @param slot The slot of the coin whose exit was challenged
     * @param owner The current claiming owner of the exit
     * @param txHash The hash of the tx used for the challenge
     */
    event ChallengedExit(uint64 indexed slot, address indexed owner, bytes32 txHash, uint256 challengingBlockNumber);

    /**
     * Event for exit response logging
     * @notice This only logs responses to `challengeBefore`
     * @param slot The slot of the coin whose challenge was responded to
     */
    event RespondedExitChallenge(uint64 indexed slot);

    /**
     * Event for logging when an exit was successfully challenged
     * @param slot The slot of the coin being reset to NOT_EXITING
     * @param owner The owner of the coin
     */
    event CoinReset(uint64 indexed slot, address indexed owner);

    /**
     * Event for exit finalization logging
     * @param slot The slot of the coin whose exit has been finalized
     * @param owner The owner of the coin whose exit has been finalized
     */
    event FinalizedExit(uint64 indexed slot, address owner);

    /**
     * Event to log the freeing of a bond
     * @param from The address of the user whose bonds have been freed
     * @param amount The bond amount which can now be withdrawn
     */
    event FreedBond(address indexed from, uint256 amount);

    /**
     * Event to log the slashing of a bond
     * @param from The address of the user whose bonds have been slashed
     * @param to The recipient of the slashed bonds
     * @param amount The bound amount which has been forfeited
     */
    event SlashedBond(address indexed from, address indexed to, uint256 amount);

    /**
     * Event to log the withdrawal of a bond
     * @param from The address of the user who withdrew bonds
     * @param amount The bond amount which has been withdrawn
     */
    event WithdrewBonds(address indexed from, uint256 amount);

    /**
     * Event to log the withdrawal of a coin
     * @param owner The address of the user who withdrew bonds
     * @param slot the slot of the coin that was exited
     * @param contractAddress The contract address where the coin is being withdrawn from
              is same as `from` when withdrawing a ETH coin
     * @param uid The uid of the coin being withdrawn if ERC721, else 0
     */
    event Withdrew(address indexed owner, uint64 indexed slot, address contractAddress, uint uid);

    /**
     * Event to pause deposits in the contract.
     * Temporarily added while the contract is being battle tested
     * @param status Boolean value of the contract's status
     */
    event Paused(bool status);

    using SafeMath for uint256;
    using Transaction for bytes;
    using Transaction for RLPReader.RLPItem[];
    using RLPReader for RLPReader.RLPItem;
    using Transaction for Transaction.AtomicSwapTX;
    using ECVerify for bytes32;
    using ChallengeLib for ChallengeLib.Challenge[];

    uint256 constant BOND_AMOUNT = 0.1 ether;

    /* An exit can be finalized after it has matured,
     * after T2 = T0 + MATURITY_PERIOD
     * An exit can be challenged in the first window
     * between T0 and T1 ( T1 = T0 + CHALLENGE_WINDOW)
     * A challenge can be responded to in the second window
     * between T1 and T2
    */
    uint256 constant MATURITY_PERIOD = 7 days;
    uint256 constant CHALLENGE_WINDOW = 3 days + 12 hours;

    /* A secret-revealing root hash can only be submitted during a period
     * after T0 and before T0 + SECRET_REVEALING_PERIOD
     * where T0 is the time the corresponding block was submitted
    */
    uint256 constant SECRET_REVEALING_PERIOD = 1 days;

    bool paused;

    /*
     * Modifiers
     */
    modifier isValidator() {
        require(vmc.checkValidator(msg.sender), "Sender is not a Validator");
        _;
    }

    modifier isTokenApproved(address _address) {
        require(vmc.allowedTokens(_address), "Contract address is not approved for deposits");
        _;
    }

    modifier isBonded() {
        require(msg.value == BOND_AMOUNT, "Transaction must be accompanied by the BOND AMOUNT");

        // Save challenger's bond
        balances[msg.sender].bonded = balances[msg.sender].bonded.add(msg.value);
        _;
    }

    modifier isState(uint64 slot, State state) {
        require(coins[slot].state == state, "Wrong coin state");
        _;
    }

    struct Balance {
        uint256 bonded;
        uint256 withdrawable;
    }

    // Each exit can only be challenged by a single challenger at a time
    struct Exit {
        uint64 slot;
        address prevOwner; // previous owner of coin
        address owner;
        uint256 createdAt;
        uint256 prevBlock;
        uint256 exitBlock;
    }

    enum State {
        NOT_EXITING,
        EXITING,
        EXITED
    }

    struct Coin {
        State state;
        address owner; // who owns that nft
        address contractAddress; // which contract does the coin belong to
        Exit exit;
        uint256 uid;
        uint256 depositBlock;
    }

    uint64 public numCoins = 0;

    mapping (address => Balance) public balances;
    mapping (uint64 => ChallengeLib.Challenge[]) challenges;
    mapping (uint64 => Coin) coins;

    struct ChildBlock {
        bytes32 root;
        uint256 createdAt;
    }

    // child chain
    uint256 public childBlockInterval = 1000;
    uint256 public currentBlock = 0;
    mapping (uint256 => ChildBlock) public childChain;
    mapping (uint256 => ChildBlock) public secretRevealingChain;


    ValidatorManagerContract vmc;
    SparseMerkleTree smt;

    constructor (ValidatorManagerContract _vmc) public {
        vmc = _vmc;
        smt = new SparseMerkleTree();
    }


    /// @dev called by a Validator to append a Plasma block to the Plasma chain
    /// @param root The transaction root hash of the Plasma block being added
    function submitBlock(uint256 blockNumber, bytes32 root) public isValidator {

        // rounding to next whole `childBlockInterval`
        require(blockNumber >= currentBlock, "A block less than currentBlock cannot be submitted");
        currentBlock = blockNumber;

        childChain[currentBlock] = ChildBlock({
            root: root,
            createdAt: block.timestamp
        });

        emit SubmittedBlock(currentBlock, root, block.timestamp);
    }

    /// @dev called by a Validator to append a Secret Revealing block to the Plasma chain
    /// @param root The transaction root hash of the Secret Revealing block being added
    function submitSecretBlock(uint256 blockNumber, bytes32 root) public isValidator {

        // rounding to next whole `childBlockInterval`
        ChildBlock memory childBlock = childChain[blockNumber];
        require(childBlock.root != 0, "A block must be submitted first in order to reveal the swap secrets");
        require((block.timestamp - childBlock.createdAt) < SECRET_REVEALING_PERIOD ,
            "Time to reveal secrets is already over");

        secretRevealingChain[blockNumber] = ChildBlock({
            root: root,
            createdAt: block.timestamp
        });

        emit SubmittedSecretBlock(blockNumber, root, block.timestamp);
    }

    /// @dev Allows anyone to deposit funds into the Plasma chain, called when
    //       contract receives ERC721
    /// @notice Appends a deposit block to the Plasma chain
    /// @param from The address of the user who is depositing a coin
    /// @param uid The uid of the ERC721 coin being deposited. This is an
    ///            identifier allocated by the ERC721 token contract; it is not
    ///            related to `slot`. If the coin is ETH or ERC20 the uid is 0
    function deposit(address from, address contractAddress, uint256 uid) private {

        require(!paused, "Contract is not accepting more deposits!");
        currentBlock = currentBlock.add(1);
        uint64 slot = uint64(bytes8(keccak256(abi.encodePacked(numCoins, msg.sender, from))));

        // Update state. Leave `exit` empty
        Coin storage coin = coins[slot];
        coin.uid = uid;
        coin.contractAddress = contractAddress;
        coin.depositBlock = currentBlock;
        coin.owner = from;
        coin.state = State.NOT_EXITING;

        childChain[currentBlock] = ChildBlock({
            // hash for deposit transactions is the hash of its slot
            root: keccak256(abi.encodePacked(slot)),
            createdAt: block.timestamp
        });

        // create a utxo at `slot`
        emit Deposit(
            slot,
            currentBlock,
            from,
            contractAddress
        );

        numCoins += 1;
    }

    /******************** EXIT RELATED ********************/

    // @dev Allows and exit of a deposited transaction
    // @param slot The slot of the coin being exited
    function startDepositExit(uint64 slot) external payable isBonded isState(slot, State.NOT_EXITING) {

        Coin memory coin = coins[slot];
        require(coin.owner == msg.sender, "Sender does not match deposit owner");
        pushExit(slot, address(0), 0, coin.depositBlock);
    }

    // @dev Allows and exit of a non-depositing transaction
    function startExit(
        uint64 slot,
        bytes calldata prevTxBytes, bytes calldata exitingTxBytes,
        bytes calldata prevTxInclusionProof, bytes calldata exitingTxInclusionProof,
        bytes calldata signature,
        uint256[2] calldata blocks
    ) external payable isBonded isState(slot, State.NOT_EXITING) {

        require(msg.sender == exitingTxBytes.getOwner(), "Sender does not match exitingTxBytes owner");
        doInclusionChecks(
            prevTxBytes, exitingTxBytes,
            prevTxInclusionProof, exitingTxInclusionProof,
            signature,
            blocks
        );

        pushExit(slot, prevTxBytes.getOwner(), blocks[0], blocks[1]);
    }

    /// @dev Verifies that consecutive two transaction involving the same coin
    ///      are valid
    /// @notice If exitingTxBytes corresponds to a deposit transaction, this function fails
    /// @param prevTxBytes The RLP-encoded transaction involving a particular
    ///        coin which took place directly before exitingTxBytes
    /// @param exitingTxBytes The RLP-encoded transaction involving a particular
    ///        coin which an exiting owner of the coin claims to be the latest
    /// @param prevTxInclusionProof An inclusion proof of prevTx
    /// @param exitingTxInclusionProof An inclusion proof of exitingTx
    /// @param signature The signature of the exitingTxBytes by the coin
    ///        owner indicated in prevTx.
    /// @param blocks An array of two block numbers, at index 0, the block
    ///        containing the prevTx and at index 1, the block containing
    ///        the exitingTx
    function doInclusionChecks(
        bytes memory prevTxBytes, bytes memory exitingTxBytes,
        bytes memory prevTxInclusionProof, bytes memory exitingTxInclusionProof,
        bytes memory signature,
        uint256[2] memory blocks
    ) public view {

        if (blocks[1] % childBlockInterval != 0) {
            revert("Please do a startDepositExit for deposited transactions");
        } else {
            checkBothIncludedAndSigned(
                prevTxBytes, exitingTxBytes, prevTxInclusionProof,
                exitingTxInclusionProof, signature,
                blocks
            );
        }
    }

    function pushExit(
        uint64 slot,
        address prevOwner,
        uint256 prevBlock,
        uint256 exitingBlock
    ) private {
        // Create exit
        Coin storage c = coins[slot];
        c.exit = Exit({
            slot: slot,
            prevOwner: prevOwner,
            owner: msg.sender,
            createdAt: block.timestamp,
            prevBlock: prevBlock,
            exitBlock: exitingBlock
        });

        // Update coin state
        c.state = State.EXITING;
        emit StartedExit(slot, msg.sender);
    }

    /// @dev Finalizes an exit, i.e. puts the exiting coin into the EXITED
    ///      state which will allow it to be withdrawn, provided the exit has
    ///      matured and has not been successfully challenged
    function finalizeExit(uint64 slot) isState(slot, State.EXITING) public {

        Coin storage coin = coins[slot];
        require((block.timestamp - coin.exit.createdAt) > MATURITY_PERIOD, "You must wait the maturity period before finalizing the exit");

        // Check if there are any pending challenges for the coin.
        // `checkPendingChallenges` will also penalize
        // for each challenge that has not been responded to
        bool hasChallenges = checkPendingChallenges(slot);

        if (!hasChallenges) {
            // Update coin's owner
            coin.owner = coin.exit.owner;
            coin.state = State.EXITED;

            // Allow the exitor to withdraw their bond
            freeBond(coin.owner);

            emit FinalizedExit(slot, coin.owner);
        } else {
            // Reset coin state since it was challenged
            coin.state = State.NOT_EXITING;
            emit CoinReset(slot, coin.owner);
        }

        delete coins[slot].exit;
    }

    function checkPendingChallenges(uint64 slot) private returns (bool hasChallenges) {

        uint256 length = challenges[slot].length;
        bool slashed;
        hasChallenges = false;
        for (uint i = 0; i < length; i++) {
            if (challenges[slot][i].txHash != 0x0) {
                // Penalize the exitor and reward the first valid challenger.
                if (!slashed) {
                    slashBond(coins[slot].exit.owner, challenges[slot][i].challenger);
                    slashed = true;
                }
                // Also free the bond of the challenger.
                freeBond(challenges[slot][i].challenger);

                // Challenge resolved, delete it
                delete challenges[slot][i];
                hasChallenges = true;
            }
        }
    }

    /// @dev Iterates through all of the initiated exits and finalizes those
    ///      which have matured without being successfully challenged
    function finalizeExits(uint64[] calldata slots) external {

        uint256 slotsLength = slots.length;
        for (uint256 i = 0; i < slotsLength; i++) {
            finalizeExit(slots[i]);
        }
    }

    function cancelExit(uint64 slot) public {

        require(coins[slot].exit.owner == msg.sender, "Only coin's owner is allowed to cancel the exit");
        delete coins[slot].exit;
        coins[slot].state = State.NOT_EXITING;
        freeBond(msg.sender);
        emit CoinReset(slot, coins[slot].owner);
    }

    function cancelExits(uint64[] calldata slots) external {

        uint256 slotsLength = slots.length;
        for (uint256 i = 0; i < slotsLength; i++) {
            cancelExit(slots[i]);
        }
    }

    /// @dev Withdraw a UTXO that has been exited
    /// @param slot The slot of the coin being withdrawn
    function withdraw(uint64 slot) external isState(slot, State.EXITED) {

        require(coins[slot].owner == msg.sender, "You do not own that UTXO");
        uint256 uid = coins[slot].uid;

        // Delete the coin that is being withdrawn
        Coin memory c = coins[slot];
        delete coins[slot];
        ERC721(c.contractAddress).safeTransferFrom(address(this), msg.sender, uid);

        emit Withdrew(
            msg.sender,
            slot,
            c.contractAddress,
            uid
        );
    }

    /******************** CHALLENGES ********************/

    /// @dev Submits proof of a transaction before prevTx as an exit challenge
    /// @notice Exitor has to call respondChallengeBefore and submit a
    ///         transaction before prevTx or prevTx itself.
    /// @param slot The slot corresponding to the coin whose exit is being challenged
    /// @param txBytes The RLP-encoded transaction involving a particular
    ///        coin which an exiting owner of the coin claims to be the latest
    /// @param txInclusionProof An inclusion proof of exitingTx
    ///        owner indicated in prevTx
    /// @param blockNumber The block containing the exitingTx
    function challengeBefore(
        uint64 slot,
        bytes calldata txBytes,
        bytes calldata txInclusionProof,
        uint256 blockNumber
    ) external payable isBonded isState(slot, State.EXITING) {

        checkBefore(slot, txBytes, txInclusionProof, blockNumber);
        setChallenged(slot, txBytes.getOwner(), blockNumber, txBytes.getHash());
    }

    /// @dev Submits proof of a later transaction that corresponds to a challenge
    /// @notice Can only be called in the second window of the exit period.
    /// @param slot The slot corresponding to the coin whose exit is being challenged
    /// @param challengingTxHash The hash of the transaction
    ///        corresponding to the challenge we're responding to
    /// @param respondingBlockNumber The block number which included the transaction
    ///        we are responding with
    /// @param respondingTransaction The RLP-encoded transaction involving a particular
    ///        coin which took place directly after challengingTransaction
    /// @param proof An inclusion proof of respondingTransaction
    /// @param signature The signature which proves a direct spend from the challenger
    function respondChallengeBefore(
        uint64 slot,
        bytes32 challengingTxHash,
        uint256 respondingBlockNumber,
        bytes calldata respondingTransaction,
        bytes calldata proof,
        bytes calldata signature
    ) external {
        // Check that the transaction being challenged exists
        require(challenges[slot].contains(challengingTxHash), "Responding to non existing challenge");

        // Get index of challenge in the challenges array
        uint256 index = uint256(challenges[slot].indexOf(challengingTxHash));

        checkResponse(slot, index, respondingBlockNumber, respondingTransaction, signature, proof);

        // If the exit was actually challenged and responded, penalize the challenger and award the responder
        slashBond(challenges[slot][index].challenger, msg.sender);

        challenges[slot].remove(challengingTxHash);
        emit RespondedExitChallenge(slot);
    }

    function checkResponse(
        uint64 slot,
        uint256 index,
        uint256 blockNumber,
        bytes memory txBytes,
        bytes memory signature,
        bytes memory proof
    ) private view {
        Transaction.TX memory txData = checkTxValid(txBytes, proof, blockNumber);
        require(txData.hash.ecverify(signature, challenges[slot][index].owner), "Invalid signature");
        require(txData.slot == slot, "Tx is referencing another slot");
        require(blockNumber > challenges[slot][index].challengingBlockNumber, "BlockNumber must be after the chalenge");
        require(blockNumber <= coins[slot].exit.exitBlock, "Cannot respond with a tx after the exit");
    }

    function challengeBetween(
        uint64 slot,
        bytes calldata challengingTransaction,
        bytes calldata proof,
        bytes calldata signature,
        uint256 challengingBlockNumber
    ) external isState(slot, State.EXITING) {

        checkBetween(slot, challengingTransaction, proof, signature, challengingBlockNumber);
        applyPenalties(slot);
    }

    function challengeAfter(
        uint64 slot,
        bytes calldata challengingTransaction,
        bytes calldata proof,
        bytes calldata signature,
        uint256 challengingBlockNumber
    ) external isState(slot, State.EXITING) {

        checkAfter(slot, challengingTransaction, proof, signature, challengingBlockNumber);
        applyPenalties(slot);
    }


    // Must challenge with a tx in between

    function checkBefore(
        uint64 slot,
        bytes memory txBytes,
        bytes memory proof,
        uint blockNumber
    ) private view {

        require(
            blockNumber <= coins[slot].exit.prevBlock,
            "Tx should be before the exit's parent block"
        );

        Transaction.TX memory txData = checkTxValid(txBytes, proof, blockNumber);
        require(txData.slot == slot, "Tx is referencing another slot");
    }


    // Check that the challenging transaction has been signed
    // by the attested previous owner of the coin in the exit
    function checkBetween(
        uint64 slot,
        bytes memory txBytes,
        bytes memory proof,
        bytes memory signature,
        uint blockNumber
    ) private view {

        require(
            coins[slot].exit.exitBlock > blockNumber &&
            coins[slot].exit.prevBlock < blockNumber,
            "Tx should be between the exit's blocks"
        );

        Transaction.TX memory txData = checkTxValid(txBytes, proof, blockNumber);
        require(txData.hash.ecverify(signature, coins[slot].exit.prevOwner), "Invalid signature");
        require(txData.slot == slot, "Tx is referencing another slot");
    }

    function checkAfter(
        uint64 slot,
        bytes memory txBytes,
        bytes memory proof,
        bytes memory signature,
        uint blockNumber
    ) private view {

        require(
            coins[slot].exit.exitBlock < blockNumber,
            "Tx should be after the exitBlock"
        );

        Transaction.TX memory txData = checkTxValid(txBytes, proof, blockNumber);
        require(txData.hash.ecverify(signature, coins[slot].exit.owner), "Invalid signature");
        require(txData.slot == slot, "Tx is referencing another slot");
        require(txData.prevBlock == coins[slot].exit.exitBlock, "Not a direct spend");
    }

    function applyPenalties(uint64 slot) private {

        // Apply penalties and change state
        slashBond(coins[slot].exit.owner, msg.sender);
        coins[slot].state = State.NOT_EXITING;
        delete coins[slot].exit;
        emit CoinReset(slot, coins[slot].owner);
    }

    /// @param slot The slot of the coin being challenged
    /// @param owner The user claimed to be the true owner of the coin
    function setChallenged(uint64 slot, address owner, uint256 challengingBlockNumber, bytes32 txHash) private {

        // Require that the challenge is in the first half of the challenge window
        require(block.timestamp <= coins[slot].exit.createdAt + CHALLENGE_WINDOW, "Challenge windows is over");

        require(!challenges[slot].contains(txHash),
            "Transaction used for challenge already");

        // Need to save the exiting transaction's owner, to verify
        // that the response is valid
        challenges[slot].push(
            ChallengeLib.Challenge({
                owner: owner,
                challenger: msg.sender,
                txHash: txHash,
                challengingBlockNumber: challengingBlockNumber
            })
        );

        emit ChallengedExit(slot, owner, txHash, challengingBlockNumber);
    }

    /******************** BOND RELATED ********************/

    function freeBond(address from) private {

        balances[from].bonded = balances[from].bonded.sub(BOND_AMOUNT);
        balances[from].withdrawable = balances[from].withdrawable.add(BOND_AMOUNT);
        emit FreedBond(from, BOND_AMOUNT);
    }

    function withdrawBonds() external {

        // Can only withdraw bond if the msg.sender
        uint256 amount = balances[msg.sender].withdrawable;
        balances[msg.sender].withdrawable = 0; // no reentrancy!

        msg.sender.transfer(amount);
        emit WithdrewBonds(msg.sender, amount);
    }

    function slashBond(address from, address to) private {

        balances[from].bonded = balances[from].bonded.sub(BOND_AMOUNT);
        balances[to].withdrawable = balances[to].withdrawable.add(BOND_AMOUNT);
        emit SlashedBond(from, to, BOND_AMOUNT);
    }

    /******************** PROOF CHECKING ********************/

    function checkBothIncludedAndSigned(
        bytes memory prevTxBytes, bytes memory exitingTxBytes,
        bytes memory prevTxInclusionProof, bytes memory exitingTxInclusionProof,
        bytes memory signature,
        uint256[2] memory blocks
    ) private view {

        require(blocks[0] < blocks[1], "Block on the first index must be the earlier of the 2 blocks");

        Transaction.TX memory prevTxData    = checkTxValid(prevTxBytes, prevTxInclusionProof, blocks[0]);
        Transaction.TX memory exitingTxData = checkTxValid(exitingTxBytes, exitingTxInclusionProof, blocks[1]);

        // Both transactions need to be referring to the same slot
        require(exitingTxData.slot == prevTxData.slot,"Slot on the ExitingTx does not match that on the prevTx");

        // The exiting transaction must be signed by the previous transaciton's receiver
        require(exitingTxData.hash.ecverify(signature, prevTxData.receiver), "Invalid signature");
    }

    function checkTX(
        bytes memory txBytes,
        bytes memory proof,
        uint256 blockNumber
    ) public view {

        checkTxValid(txBytes, proof, blockNumber);
    }


    function checkTxValid(
        bytes memory txBytes,
        bytes memory proof,
        uint256 blockNumber
    ) private view returns(Transaction.TX memory) {

        RLPReader.RLPItem[] memory rlpTx = txBytes.toRLPItems();

        if(rlpTx.isBasicTransaction()) {
            //Basic transactions only validate are included
            Transaction.TX memory txData = rlpTx.getBasicTx(txBytes);
            checkHashIncluded(txData.slot, txData.hash, blockNumber, proof);
            return txData;

        } else if(rlpTx.isAtomicSwap()) {
            ChildBlock memory secretRevealingBlock = secretRevealingChain[blockNumber];

            if(secretRevealingBlock.root != 0) {
                Transaction.AtomicSwapTX[] memory txsData = rlpTx.getAtomicSwapTxs();

                //Check signature B -> A. A -> B signature is checked in outside if this function
                require(txsData[1].hash.ecverify(txsData[1].signature, txsData[1].prevOwner), "Invalid signature B in atomic swap");

                RLPReader.RLPItem[] memory proofs = proof.toRLPItems();
                require(proofs.length == 4, "4 proof must be submitted for an atomic swap");
                checkHashIncluded(txsData[0].slot, txsData[0].hash, blockNumber, proofs[0].toBytes());
                checkHashIncluded(txsData[1].slot, txsData[1].hash, blockNumber, proofs[1].toBytes());
                checkHashIncludedSecret(txsData[0].slot, txsData[0].secret, blockNumber, proofs[2].toBytes());
                checkHashIncludedSecret(txsData[1].slot, txsData[1].secret, blockNumber, proofs[3].toBytes());

                return txsData[0].toBasicTx();
            } else {
                ChildBlock memory childBlock = childChain[blockNumber];
                if((block.timestamp - childBlock.createdAt) > SECRET_REVEALING_PERIOD) {
                    revert("Secret was never revealed for this block, swap is invalid");
                } else {
                    revert("Secret has not yet been revealed, there is still time to commit the transaction");
                }
            }
        } else {
            revert("txBytes do not correspond neither to basic TX nor to Atomic swap");
        }
    }


    function checkHashIncluded(
        uint64 slot,
        bytes32 txHash,
        uint256 blockNumber,
        bytes memory proof
    ) private view {
        bytes32 root = childChain[blockNumber].root;

        if (blockNumber % childBlockInterval != 0) {
            // Check against block root for deposit block numbers
            require(txHash == root, "Transaction hash does not match rootHash");
        } else {
            // Check against merkle tree for all other block numbers
            require(
                checkMembership(
                    txHash,
                    root,
                    slot,
                    proof
                ),
                "Tx not included in claimed block"
            );
        }
    }

    function checkHashIncludedSecret(
        uint64 slot,
        bytes32 secret,
        uint256 blockNumber,
        bytes memory proof
    ) private view {

        bytes32 root = secretRevealingChain[blockNumber].root;
        require(blockNumber % childBlockInterval == 0, "Trying to validate an atomic swap for a deposit block");
        // Check against merkle tree for all other block numbers
        require(
            checkMembership(
                secret,
                root,
                slot,
                proof
            ),
            "Tx secret not included in claimed block"
        );
    }

    /******************** DEPOSIT FUNCTIONS ********************/

    function pause() external isValidator {
        paused = true;
        emit Paused(true);
    }

    function unpause() external isValidator {
        paused = false;
        emit Paused(false);
    }

    function() external payable {
        //TODO: Not quite sure about this
        require(false, "This contract does not receive money");
    }

    function onERC721Received(address /*operator*/, address from, uint256 tokenId, bytes memory /*data*/)
    public isTokenApproved(msg.sender) returns (bytes4) {

        require(ERC721(msg.sender).ownerOf(tokenId) == address(this), "Token was not transfered correctly");
        deposit(from, msg.sender, tokenId);
        return this.onERC721Received.selector;
    }

    // Approve and Deposit function for 2-step deposits without having to approve the token by the validators
    // Requires first to have called `approve` on the specified ERC721 contract
    function depositERC721(uint256 uid, address contractAddress) external {
        ERC721(contractAddress).safeTransferFrom(msg.sender, address(this), uid);
    }

    /******************** HELPERS ********************/

    function checkMembership(
        bytes32 txHash,
        bytes32 root,
        uint64 slot,
        bytes memory proof
    ) public view returns (bool) {

        return smt.checkMembership(
            txHash,
            root,
            slot,
            proof);
    }

    function checkInclusion(
        bytes32 txHash,
        uint256 blockNumber,
        uint64 slot,
        bytes memory proof
    ) public view returns (bool) {

        ChildBlock memory childBlock = childChain[blockNumber];
        if (blockNumber % childBlockInterval != 0) {
            return txHash == childBlock.root && keccak256(abi.encodePacked(slot)) == childBlock.root;
        } else {
            return checkMembership(txHash, childBlock.root, slot, proof);
        }
    }

    function checkValidationAndInclusion(
        bytes calldata txBytes,
        bytes calldata proof,
        uint256 blockNumber
    ) external view returns (bool) {

        checkTxValid(txBytes, proof, blockNumber);
        return true;
    }

    function getPlasmaCoin(uint64 slot) external view returns(uint256, uint256, address, State, address) {

        Coin memory c = coins[slot];
        return (c.uid, c.depositBlock, c.owner, c.state, c.contractAddress);
    }

    function getChallenge(uint64 slot, bytes32 txHash)
    external view returns(address, address, bytes32, uint256) {

        uint256 index = uint256(challenges[slot].indexOf(txHash));
        ChallengeLib.Challenge memory c = challenges[slot][index];
        return (c.owner, c.challenger, c.txHash, c.challengingBlockNumber);
    }

    function getChallenges(uint64 slot) external view returns(bytes32[] memory) {

        uint length = challenges[slot].length;
        bytes32[] memory slotChallenges = new bytes32[](length);
        for (uint i = 0; i < length; i++) {
            slotChallenges[i] = challenges[slot][i].txHash;
        }

        return slotChallenges;
    }

    function getExit(uint64 slot) external view returns(address, uint256, uint256, State, uint256) {
        Exit memory e = coins[slot].exit;
        return (e.owner, e.prevBlock, e.exitBlock, coins[slot].state, e.createdAt);
    }

    function getBlock(uint256 blockNumber) public view returns (bytes32, uint) {
        return(childChain[blockNumber].root, childChain[blockNumber].createdAt);
    }

    function getSecretBlock(uint256 blockNumber) public view returns (bytes32, uint) {
        return(secretRevealingChain[blockNumber].root, secretRevealingChain[blockNumber].createdAt);
    }

    function getBalance() external view returns(uint256, uint256) {
        // Can only withdraw bond if the msg.sender
        return (balances[msg.sender].bonded, balances[msg.sender].withdrawable);
    }
}
