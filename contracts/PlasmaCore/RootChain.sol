// Copyright Loom Network 2018 - All rights reserved, Dual licensed on GPLV3
// Learn more about Loom DappChains at https://loomx.io
// All derivitive works of this code must incluse this copyright header on every file

pragma solidity ^0.5.12;

// ERC721
import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721Receiver.sol";

// Lib deps
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./Libraries/Transaction/Transaction.sol";
import "./Libraries/ECVerify.sol";
import "./Libraries/Plasma/ChallengeLib.sol";

// SMT and VMC
import "./Supporting/ValidatorManagerContract.sol";
import "./Supporting/SparseMerkleTree.sol";
import "./Libraries/Plasma/PlasmaChallenges.sol";


contract RootChain is IERC721Receiver {

    using SafeMath for uint256;
    using Transaction for bytes;
    using Transaction for RLPReader.RLPItem[];
    using RLPReader for RLPReader.RLPItem;
    using Transaction for Transaction.AtomicSwapTX;
    using ECVerify for bytes32;
    using ChallengeLib for ChallengeLib.Challenge[];
    using PlasmaChallenges for RootChain.Exit;

    ///////////////////////////////////////////////////////////////////////////////////
    ////   EVENTS
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * Event for coin deposit logging.
     * @notice The Deposit event indicates that a deposit block has been added to the Plasma chain
     * @param slot            Plasma slot, a unique identifier, assigned to the deposit
     * @param blockNumber     The index of the block in which a deposit transaction is included
     * @param from            The address of the depositor
     * @param contractAddress The address of the contract making the deposit
     */
    event Deposit(uint64 indexed slot, uint256 blockNumber, address indexed from, address indexed contractAddress);

    /**
     * Event for block submission logging
     * @notice The event indicates the addition of a new Plasma block
     * @param blockNumber The block number of the submitted block
     * @param root        The root hash of the Merkle tree containing all of a block's transactions.
     * @param timestamp   The time when a block was added to the Plasma chain
     */
    event SubmittedBlock(uint256 blockNumber, bytes32 root, uint256 timestamp);

    /**
     * Event for secret-revealing block submission logging
     * @notice The event indicates the addition of a new Secret Revealing block
     * @param blockNumber The block number of the submitted block
     * @param root        The root hash of the Merkle tree containing all of a block's secrets.
     * @param timestamp   The time when a block was added to the Plasma chain
     */
    event SubmittedSecretBlock(uint256 blockNumber, bytes32 root, uint256 timestamp);

    /**
     * Event for logging exit starts
     * @param slot  The slot of the coin being exited
     * @param owner The user who claims to own the coin being exited
     */
    event StartedExit(uint64 indexed slot, address indexed owner);

    /**
     * Event for exit challenge logging
     * @notice This event only fires if `challengeBefore` is called.
     * @param slot   The slot of the coin whose exit was challenged
     * @param owner  The current claiming owner of the exit
     * @param txHash The hash of the tx used for the challenge
     */
    event ChallengedExit(uint64 indexed slot, address indexed owner, bytes32 txHash, uint256 challengingBlockNumber);

    /**
     * Event for exit response logging
     * @notice This only logs responses to `challengeBefore`
     * @param slot The slot of the coin whose challenge was responded to
     */
    event RespondedExitChallenge(uint64 indexed slot,  address indexed owner,  address indexed challenger);

    /**
     * Event for logging when an exit was successfully challenged
     * @param slot The slot of the coin being reset to NOT_EXITING
     * @param owner The owner of the coin
     */
    event CoinReset(uint64 indexed slot, address indexed owner);

    /**
     * Event for exit finalization logging
     * @param slot  The slot of the coin whose exit has been finalized
     * @param owner The owner of the coin whose exit has been finalized
     */
    event FinalizedExit(uint64 indexed slot, address indexed owner);

    /**
     * Event to log the freeing of a bond
     * @param from   The address of the user whose bonds have been freed
     * @param amount The bond amount which can now be withdrawn
     */
    event FreedBond(address indexed from, uint256 amount);

    /**
     * Event to log the slashing of a bond
     * @param from   The address of the user whose bonds have been slashed
     * @param to     The recipient of the slashed bonds
     * @param amount The bound amount which has been forfeited
     */
    event SlashedBond(address indexed from, address indexed to, uint256 amount);

    /**
     * Event to log the withdrawal of a bond
     * @param from   The address of the user who withdrew bonds
     * @param amount The bond amount which has been withdrawn
     */
    event WithdrewBonds(address indexed from, uint256 amount);

    /**
     * Event to log the withdrawal of a coin
     * @param owner           The address of the user who withdrew bonds
     * @param slot            The slot of the coin that was exited
     * @param contractAddress The contract address where the coin is being withdrawn from is same as
     *                        `from` when withdrawing a ETH coin
     * @param uid             The uid of the coin being withdrawn if ERC721, else 0
     */
    event Withdrew(address indexed owner, uint64 indexed slot, address contractAddress, uint uid);

    /**
     * Event to pause deposits in the contract.
     * Temporarily added while the contract is being battle tested
     * @param status Boolean value of the contract's status
     */
    event Paused(bool status);

    ///////////////////////////////////////////////////////////////////////////////////
    ////   Structs
    //////////////////////////////////////////////////////////////////////////////////

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

    struct ChildBlock {
        bytes32 root;
        uint256 createdAt;
    }


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

    uint64 public numCoins = 0;
    mapping (uint64 => Coin) coins;

    uint256 constant BOND_AMOUNT = 0.1 ether;
    mapping (address => Balance) public balances;
    mapping (uint64 => ChallengeLib.Challenge[]) challenges;

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

    function pause() external isValidator {
        paused = true;
        emit Paused(true);
    }

    function unpause() external isValidator {
        paused = false;
        emit Paused(false);
    }

    function() external payable {
        revert("This contract does not receive money");
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////   Block submissions
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev called by a Validator to append a Plasma block to the Plasma chain
     * @notice Emits SubmittedBlock event
     * @param blockNumber Number of the block to submit
     * @param root        The transaction root hash of the Plasma block being added
    */
    function submitBlock(uint256 blockNumber, bytes32 root) public isValidator {
        require(blockNumber >= currentBlock, "A block less than currentBlock cannot be submitted");
        require(blockNumber % childBlockInterval == 0, "A submitted block must be childBlockInterval numbered");

        currentBlock = blockNumber;
        childChain[currentBlock] = ChildBlock({
            root: root,
            createdAt: block.timestamp
        });

        emit SubmittedBlock(currentBlock, root, block.timestamp);
    }

    /**
     * @dev called by a Validator to append a Secret Revealing Plasma block to the Plasma chain. It has to be withing
     *      SECRET_REVEALING_PERIOD from the submission of the blockNumber block.
     * @notice Emits SubmittedSecretBlock event
     * @param blockNumber Number of the block corresponding to this secretBlock
     * @param root        The transaction root hash of the Plasma block being added
    */
    function submitSecretBlock(uint256 blockNumber, bytes32 root) public isValidator {

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

    ///////////////////////////////////////////////////////////////////////////////////
    ////   Deposit
    //////////////////////////////////////////////////////////////////////////////////

    function onERC721Received(
        address /*operator*/,
        address from,
        uint256 tokenId,
        bytes memory /*data*/
    )public isTokenApproved(msg.sender) returns (bytes4) {

        require(ERC721(msg.sender).ownerOf(tokenId) == address(this), "Token was not transfered correctly");
        deposit(from, msg.sender, tokenId);
        return this.onERC721Received.selector;
    }

    /** @dev Allows anyone to deposit funds into the Plasma chain, called when contract receives ERC721
      * @notice Appends a deposit block to the Plasma chain
      * @notice Emits Deposit event
      * @param from             The address of the user who is depositing a coin
      * @param contractAddress  The address implementing the ERC721 creator of the token
      * @param uid              The uid of the ERC721 coin being deposited. This is an identifier allocated by the
      *                         ERC721 token contract; it is not related to `slot`.
      */
    function deposit(address from, address contractAddress, uint256 uid) private {

        require(!paused, "Contract is not accepting more deposits!");
        //Deposit blocks are added by 1 each time, so there can be interpolated within the childBlockInterval without problem.
        currentBlock = currentBlock.add(1);

        //Slot is created uniquely for any deposit. If the same coin is deposited again after exited, it will have a new slot.
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

        numCoins += 1;

        emit Deposit(slot, currentBlock, from, contractAddress);
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////   Exits
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Allows and exit of a deposit transaction
     * @notice Emits StartedExit event
     * @param slot The slot of the coin being exited
     */
    function startDepositExit(uint64 slot) external payable isBonded isState(slot, State.NOT_EXITING) {

        Coin memory coin = coins[slot];
        require(coin.owner == msg.sender, "Sender does not match deposit owner");
        pushExit(slot, address(0), 0, coin.depositBlock);
    }

    /**
     * @dev Allows and exit of a non-deposit transaction. See `checkBothIncludedAndSigned` for conditions
     * @notice Emits StartedExit event
     * @notice must be bonded with BOND_AMOUNT
     * @param slot                    The slot of the coin being exited
     * @param prevTxBytes             The bytes corresponding to the immediate previous transaction to exitingTxBytes.
     * @param exitingTxBytes          The bytes transaction to be exited. Needs to be the last valid transaction of the
     *                                slot in order not to be able to be challenged. Owner of it must be msg.sender.
     * @param prevTxInclusionProof    An inclusion proof of `prevTxBytes`
     * @param exitingTxInclusionProof An inclusion proof of `exitingTxBytes`
     * @param signature               Signature of exitingTxBytes. Must be signed by the recipient of prevTxBytes.
     * @param blocks                  The blocks (array of size 2) corresponding to prevTxBytes and exitingTxBytes in that order
     *                                to validate their correct inclusion
     */
    function startExit(
        uint64 slot,
        bytes calldata prevTxBytes, bytes calldata exitingTxBytes,
        bytes calldata prevTxInclusionProof, bytes calldata exitingTxInclusionProof,
        bytes calldata signature,
        uint256[2] calldata blocks
    ) external payable isBonded isState(slot, State.NOT_EXITING) {

        require(msg.sender == exitingTxBytes.getOwner(), "Sender does not match exitingTxBytes owner");
        if (blocks[1] % childBlockInterval != 0) {
            revert("Please do a startDepositExit for deposited transactions");
        }

        checkBothIncludedAndSigned(
            prevTxBytes, exitingTxBytes, prevTxInclusionProof, exitingTxInclusionProof, signature,blocks
        );

        pushExit(slot, prevTxBytes.getOwner(), blocks[0], blocks[1]);
    }

    /**
      * @dev Generates an Exit and adds it it to the coin.
      * @notice Emits StartedExit event
      * @notice Adds exit to coin and changes it state to EXITING
      * @param slot          The slot of the coin being exited
      * @param prevOwner     The supposed previous to last owner of the coin in the plasma chain.
      * @param prevBlock     The supposed previous to last block that the coin was spent on
      * @param exitingBlock  The supposed last block that the coin was spent on
      */
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


    /**
      * @dev Finalizes an exit, i.e. puts the exiting coin into the EXITED state and withdraws it,
      *      provided the exit has matured and has not been successfully challenged, else if a challenge is present,
      *      resets the coin and awards the challenger with the bond.
      * @notice Changes coin's state to EXITED
      * @notice Emits FinalizedExit event if no challenges are present
      * @notice Emits Withdrew event if no challenges are present
      * @notice Emits CoinReset event if there are challenges present
      * @param slot          The slot of the coin being exited
      */
    function finalizeExit(uint64 slot) isState(slot, State.EXITING) public {

        Coin storage coin = coins[slot];
        require((block.timestamp - coin.exit.createdAt) > MATURITY_PERIOD, "You must wait the maturity period before finalizing the exit");

        // Check if there are any pending challenges for the coin. `checkPendingChallenges` will also penalize
        // for each challenge that has not been responded to
        bool hasChallenges = checkPendingChallenges(slot);

        if (!hasChallenges) {
            // Update coin's owner
            coin.owner = coin.exit.owner;
            coin.state = State.EXITED;

            // Allow the exitor to withdraw their bond
            freeBond(coin.owner);

            emit FinalizedExit(slot, coin.owner);
            withdraw(slot);
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

    /**
      * @dev Withdraws a token that has been exited.
      * @notice Emits Withdrew event
      * @param slot          The slot of the coin being withdrawn
      */
    function withdraw(uint64 slot) private isState(slot, State.EXITED) {
        require(coins[slot].owner == msg.sender, "You do not own that slot");
        uint256 uid = coins[slot].uid;

        // Delete the coin that is being withdrawn
        Coin memory c = coins[slot];
        delete coins[slot];
        ERC721(c.contractAddress).safeTransferFrom(address(this), msg.sender, uid);

        emit Withdrew(msg.sender, slot, c.contractAddress, uid);
    }

    /**
      * @dev Cancels an ongoing exit, resetting the coin to not-exited.
      * @notice Emits CoinReset event
      * @param slot          The slot of the coin being reset
      */
    function cancelExit(uint64 slot) public {

        require(coins[slot].exit.owner == msg.sender, "Only coin's owner is allowed to cancel the exit");
        require(challenges[slot][0].txHash != 0x0, "Can't cancel an exit with a current challenge");
        delete coins[slot].exit;
        coins[slot].state = State.NOT_EXITING;
        freeBond(msg.sender);
        emit CoinReset(slot, coins[slot].owner);
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////   Challenges
    //////////////////////////////////////////////////////////////////////////////////

   /**
    * @dev Allows a user to challenge an exit, by providing a direct spend, in order to prevent the exit of an unauthorized token.
    * @notice Emits CoinReset event
    * @notice Sets coin's state to NOT_EXITING
    * @param slot        The slot to be challenged
    * @param txBytes     RLP encoded bytes of the transaction to make a Challenge After. See CheckAfter for conditions.
    * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
    * @param signature   Signature of the txBytes proving the validity of it.
    * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof
    */
    function challengeAfter(
        uint64 slot,
        bytes calldata txBytes,
        bytes calldata proof,
        bytes calldata signature,
        uint256 blockNumber
    ) external isState(slot, State.EXITING) {
        Exit memory exit = coins[slot].exit;
        exit.checkAfter(this, txBytes, proof, signature, blockNumber);
        applyPenalties(slot);
    }

    /**
    * @dev Allows a user to challenge an exit, by providing a previous double spend, in order to prevent the exit of an unauthorized token.
    * @notice Emits CoinReset event
    * @notice Sets coin's state to NOT_EXITING
    * @param slot        The slot to be challenged
    * @param txBytes     RLP encoded bytes of the transaction to make a Challenge Between. See CheckBetween for conditions.
    * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
    * @param signature   Signature of the txBytes proving the validity of it.
    * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof
    */
    function challengeBetween(
        uint64 slot,
        bytes calldata txBytes,
        bytes calldata proof,
        bytes calldata signature,
        uint256 blockNumber
    ) external isState(slot, State.EXITING) {
        Exit memory exit = coins[slot].exit;
        exit.checkBetween(this, txBytes, proof, signature, blockNumber);
        applyPenalties(slot);
    }

    /**
     * @dev Apply penalties for un unlawful exit attempt
     * @notice Set the coin's state to NOT_EXITING
     * @notice Emits CoinReset event
     * @notice The bond is given to the responder.
     * @param slot                  The slot challenged
     */
    function applyPenalties(uint64 slot) private {

        // Apply penalties and change state
        slashBond(coins[slot].exit.owner, msg.sender);
        coins[slot].state = State.NOT_EXITING;
        delete coins[slot].exit;
        emit CoinReset(slot, coins[slot].owner);
    }

  /**
   * @dev Allows a user to create a Plasma Challenge targeting an exit in order to prevent the use of unauthorized tokens.
   *      A plasma challenge is any previous transaction of the token that must be proved invalid by a direct spend of it.
   * @notice Pushes a ChallengeLib.Challenge to challenges
   * @notice Emits ChallengedExit event
   * @notice A bond must be locked to prevent unlawful challenges. If the challenge is not answered, the bond is returned.
   * @param slot        The slot to be challenged
   * @param txBytes     RLP encoded bytes of the transaction to make a Challenge Before. See CheckBefore for conditions.
   * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
   * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof
   */
    function challengeBefore(
        uint64 slot,
        bytes calldata txBytes,
        bytes calldata proof,
        uint256 blockNumber
    ) external payable isBonded isState(slot, State.EXITING) {

        coins[slot].exit.checkBefore(this, txBytes, proof, blockNumber);
        setChallenged(slot, txBytes.getOwner(), blockNumber, txBytes.getHash());
    }

   /**
    * @dev Pushes a challenge for a given slot
    * @notice Pushes a ChallengeLib.Challenge to challenges
    * @notice Emits ChallengedExit event
    * @notice The bond is given to the responder.
    * @param slot                   The slot to be challenged
    * @param owner                  The claimed owner of the challenge
    * @param owner                  The claimed owner of the challenge
    * @param challengingBlockNumber BlockNumber of the challenging transaction
    * @param txHash                 The hash of the challenging transaction
    */
    function setChallenged(uint64 slot, address owner, uint256 challengingBlockNumber, bytes32 txHash) private {

        // Require that the challenge is in the first half of the challenge window
        require(block.timestamp <= coins[slot].exit.createdAt + CHALLENGE_WINDOW, "Challenge windows is over");

        require(!challenges[slot].contains(txHash),
            "Transaction used for challenge already");

        // Need to save the exiting transaction's owner, to verify
        // that the response is valid
        challenges[slot].push(
            ChallengeLib.Challenge({
            exitor: coins[slot].exit.owner,
            owner: owner,
            challenger: msg.sender,
            txHash: txHash,
            challengingBlockNumber: challengingBlockNumber
            })
        );

        emit ChallengedExit(slot, owner, txHash, challengingBlockNumber);
    }

    /**
     * @dev Allows a user to respond to a Plasma Challenge targeting a funded channel's exit. For validity go to CheckResponse
     * @notice Removes a ChallengeLib.Challenge to challenges
     * @notice Emits RespondedExitChallenge event
     * @notice The bond is given to the responder.
     * @param slot                   The slot to be challenged
     * @param challengingTxHash     Hash of the transaction being challenged with.
     * @param respondingBlockNumber BlockNumber of the respondingTransaction to be checked for the inclusion proof.
     * @param respondingTransaction Transaction signed by the challengingTxHash owner showing a spent
     * @param proof                 Bytes needed for the proof of inclusion of respondingTransaction in the Plasma block
     * @param signature             Signature of the respondingTransaction to prove its validity
     */
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

        ChallengeLib.Challenge memory challenge = challenges[slot][index];
        Exit memory exit = coins[slot].exit;
        exit.checkResponse(this, challenge, respondingBlockNumber, respondingTransaction, signature, proof);

        // If the exit was actually challenged and responded, penalize the challenger and award the responder
        slashBond(challenge.challenger, msg.sender);
        challenges[slot].remove(challengingTxHash);
        emit RespondedExitChallenge(slot, exit.owner, challenge.challenger);
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////   Bonds
    //////////////////////////////////////////////////////////////////////////////////

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

    ///////////////////////////////////////////////////////////////////////////////////
    ////   Proofs
    //////////////////////////////////////////////////////////////////////////////////

   /**
    * @dev Verifies that consecutive two transaction involving the same coin are valid
    * @notice If exitingTxBytes corresponds to a deposit transaction, this function fails
    * @param prevTxBytes    The RLP-encoded transaction involving a coin which took place directly before exitingTxBytes
    * @param exitingTxBytes The RLP-encoded transaction involving a coin which an exiting owner of the coin claims to be the latest
    * @param prevTxInclusionProof    An inclusion proof of prevTx
    * @param exitingTxInclusionProof An inclusion proof of exitingTx
    * @param signature The signature of the exitingTxBytes by the coin owner indicated in prevTx.
    * @param blocks An array of two block numbers, at index 0, the block containing the prevTx and at index 1, the block containing
    *        the exitingTx
    */
    function checkBothIncludedAndSigned(
        bytes memory prevTxBytes, bytes memory exitingTxBytes,
        bytes memory prevTxInclusionProof, bytes memory exitingTxInclusionProof,
        bytes memory signature,
        uint256[2] memory blocks
    ) public view {

        require(blocks[0] < blocks[1], "Block on the first index must be the earlier of the 2 blocks");

        Transaction.TX memory prevTxData    = checkTxValid(prevTxBytes, prevTxInclusionProof, blocks[0]);
        Transaction.TX memory exitingTxData = checkTxValid(exitingTxBytes, exitingTxInclusionProof, blocks[1]);

        // Both transactions need to be referring to the same slot
        require(exitingTxData.slot == prevTxData.slot,"Slot on the ExitingTx does not match that on the prevTx");

        // The exiting transaction must be signed by the previous transaciton's receiver
        require(exitingTxData.hash.ecverify(signature, prevTxData.receiver), "Invalid signature");
    }

    //Non-returning wrapper for checkTxValid
    function checkTX(bytes memory txBytes, bytes memory proof, uint256 blockNumber) public view returns (bool) {

        checkTxValid(txBytes, proof, blockNumber);
        return true;
    }

    /**
     * @dev Verifies that consecutive two transaction involving the same coin are valid
     * @notice If exitingTxBytes corresponds to a deposit transaction, this function fails
     * @param txBytes     The RLP-encoded transaction involving a coin
     * @param proof       An inclusion proof of txBytes
     * @param blockNumber The blockNumber that included txBytes
     */
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

   /**
    * @dev Checks whether a transactionHash was submitted in a block by doing a Merkle Proof
    * @param slot        Slot where the transaction was included
    * @param txHash      Hash to be checked was included
    * @param blockNumber The blockNumber that included txHash
    * @param proof       An inclusion proof of txHash
    */
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

    /**
     * @dev Checks whether a secret was included in a secret revealing block by doing a Merkle Proof
     * @param slot        Slot where the transaction was included
     * @param secret      Secret to be included
     * @param blockNumber The blockNumber that included txBytes
     * @param proof       An inclusion proof of txBytes
     */
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

    //public wrapper for SMT.checkMembership
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

    //Public checkInclusion for validation
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

    ///////////////////////////////////////////////////////////////////////////////////
    ////   Getters
    //////////////////////////////////////////////////////////////////////////////////

    function getPlasmaCoin(uint64 slot) external view returns(uint256, uint256, address, State, address) {

        Coin memory c = coins[slot];
        return (c.uid, c.depositBlock, c.owner, c.state, c.contractAddress);
    }

    function getChallenge(uint64 slot, bytes32 txHash) external view returns(address, address, bytes32, uint256) {

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

    ///////////////////////////////////////////////////////////////////////////////////
    ////   Modifiers
    //////////////////////////////////////////////////////////////////////////////////

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

}
