pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/drafts/Counters.sol";

import "./Libraries/Battles/Adjudicator.sol";
import "./Libraries/Transaction/Transaction.sol";
import "./Libraries/ChallengeLib.sol";
import "./RootChain.sol";
import "./Libraries/Battles/Rules.sol";


//Plasma Channel Manager
contract PlasmaCM {
    using Adjudicators for FMChannel;
    using Counters for Counters.Counter;
    using ECVerify for bytes32;
    using State for State.StateStruct;
    using Transaction for bytes;
    using ChallengeLib for ChallengeLib.Challenge[];

    ///////////////////////////////////////////////////////////////////////////////////
    ////   EVENTS
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * Event for channel initiated waiting for opponent's response.
     * @param channelId   Unique identifier of the channel
     * @param creator     Creator of the channel, also known as player
     * @param opponent    Opponent of the channel, require to fund to start the channel
     * @param channelType The address of PlasmaTurnGame implementation contract which determines the game
     */
    event ChannelInitiated(uint channelId, address indexed creator, address indexed opponent, address channelType);

    /**
     * Event for channel funding, after both participants have secured the stake and agreed on an initial state.
     * @param channelId    Unique identifier of the channel
     * @param creator      Creator of the channel, also known as player
     * @param opponent     Opponent of the channel, who funded the channel
     * @param channelType  The address of PlasmaTurnGame implementation contract which determines the game
     * @param initialState The encoded state, determined how to be decoded by the channelType, that will be defined as
                           the starting point of this channel, that both parties agreed on.
     */
    event ChannelFunded(uint channelId, address indexed creator, address indexed opponent, address channelType, bytes initialState);

    /**
     * Event for channel conclusion
     * @notice A channel can be concluded by:
                A) Being close in an unfunded state by the creator
                B) Being close in case of a force move challenge is not answered
                C) The final states are provided and validated
     * @param channelId   Unique identifier of the channel
     * @param creator     Creator of the channel, also known as player
     * @param opponent    Opponent of the channel
     * @param channelType The address of PlasmaTurnGame implementation contract which determines the game
     */
    event ChannelConcluded(uint channelId, address indexed creator, address indexed opponent, address channelType);

    /**
     * Event for the closure of a channel due to a Plasma challenge being issued.
     * @notice This event is generated when ChallengeAfter or ChallengeBetween is called, closing the channel and giving
               the stake to the challenger.
     * @param channelId   Unique identifier of the channel
     * @param exitIndex   Index corresponding to the exit's index to be challenged
     * @param creator     Creator of the channel, also known as player
     * @param opponent    Opponent of the channel
     */
    event ChannelChallenged(uint indexed channelId, uint exitIndex, address indexed creator, address indexed opponent);

    /**
     * Event for the creation of a Plasma challenge inside a channel.
     * @notice This event is generated when ChallengeBefore is called, forcing someone to ask the challenge before
               the challenge window ends or surrendering the channel's stake.
     * @param channelId   Unique identifier of the channel
     * @param exitIndex   Index corresponding to the exit's index to be challenged
     * @param txHash      Hash of the challenging transaction
     * @param creator     Creator of the channel, also known as player
     * @param opponent    Opponent of the channel
     * @param challenger  Address of the challenge issuer
     */
    event ChallengeRequest(
        uint indexed channelId, uint exitIndex, bytes32 txHash,
        address indexed creator, address indexed opponent, address challenger
    );

    /**
      * Event for the response of a Plasma challenge inside a channel.
      * @notice This event is generated when respondChallengeBefore is called, invalidating the plasma challenge.
      * @param channelId   Unique identifier of the channel
      * @param exitIndex   Index corresponding to the exit's index challenged
      * @param txHash      Hash of the challenging transaction
      * @param creator     Creator of the channel, also known as player
      * @param opponent    Opponent of the channel
      * @param challenger  Address of the challenge issuer
      */
    event ChallengeResponded(
        uint indexed channelId, uint exitIndex, bytes32 txHash,
        address indexed creator, address indexed opponent, address challenger
    );

    /**
      * Event for the request of Force Move challenge inside a channel.
      * @notice This event is generated when ForceMove or alternativeRespondWithMove is called, forcing a player
                to answer or surrender the channel's stake.
      * @param channelId   Unique identifier of the channel
      * @param state       Game State to be answered to
      */
    event ForceMoveRequested(uint indexed channelId, State.StateStruct state);

    /**
      * Event for the response of Force Move challenge inside a channel.
      * @notice This event is generated when respondWithMove or alternativeRespondWithMove is called, notifying the players
                of the state to continue from the channel
      * @param channelId   Unique identifier of the channel
      * @param nextState   Game State answer, to be used to continue the channel
      * @param signature   Signature corresponding to nextState
      */
    event ForceMoveResponded(uint indexed channelId, State.StateStruct nextState, bytes signature);

    ///////////////////////////////////////////////////////////////////////////////////
    ////            VARIABLES
    //////////////////////////////////////////////////////////////////////////////////
    enum ChannelState { INITIATED, FUNDED, SUSPENDED, CLOSED, CHALLENGED }

    //Force Move Channel
    struct FMChannel {
        uint256 channelId;
        address channelType;
        uint fundedTimestamp;
        uint256 stake;
        address[2] players;
        bytes32 initialArgumentsHash;
        ChannelState state;
        Rules.Challenge forceMoveChallenge;
    }

    mapping (uint => FMChannel) channels;
    mapping (uint => ChallengeLib.Challenge[]) challenges;
    mapping (uint => RootChain.Exit[]) exits;
    mapping (address => uint) funds;

    Counters.Counter channelCounter;
    RootChain rootChain;

    uint256 constant MINIMAL_BET = 0.01 ether;
    uint256 constant CHALLENGE_BOND = 0.1 ether;
    uint256 constant CHALLENGE_RESPOND_PERIOD = 24 hours;
    uint256 constant CHALLENGE_PERIOD = 12 hours;

    constructor(RootChain _rootChain) public {
        rootChain = _rootChain;
    }

    function () external payable {
        revert("Please send funds using the FundChannel");
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////            Channel Creation and Closure
    //////////////////////////////////////////////////////////////////////////////////

    /**
      * @dev Allows a player to create a Force Move Channel against an opponent, staking an amount of ether declaring
      *      the winner of it to be able to reclaim it, using within it any plasma tokens deposited on rootChain.
      * @notice Appends a FMChannel to channels, ExitData to exits.
      * @notice Emits ChannelInitiated event
      * @param channelType  The address of the contract implementing PlasmaTurnGame interface to determine the type of game
      * @param opponent     The address of the user who will be facing the creator
      * @param stake        The amount of money to be staking. Same amount of ether must accompany the function call.
      * @param initialGameAttributes The encoded initial state to be decoded by the channelType
      * @param exitData     The encoded exitData to be decoded by the channelType of the creator's plasma tokens being used by
      *                     the creator.
      */
    function initiateChannel(
        address channelType,
        address opponent,
        uint stake,
        bytes calldata initialGameAttributes,
        bytes calldata exitData
    ) external payable Payment(stake) {

        channelCounter.increment();

        address[2] memory addresses;
        addresses[0] = msg.sender;
        addresses[1] = opponent;

        RootChain.Exit[] memory exited = PlasmaTurnGame(channelType).validateStartState(
            initialGameAttributes, addresses, 0, exitData);
        for(uint i; i < exited.length; i++) {
            exits[channelCounter.current()].push(exited[i]);
        }

        Rules.Challenge memory challenge;
        FMChannel memory channel = FMChannel(
            channelCounter.current(),
            channelType,
            0, // to be filled when channel is funded
            stake,
            addresses,
            keccak256(initialGameAttributes),
            ChannelState.INITIATED,
            challenge
        );

        channels[channel.channelId] = channel;

        // Emit events
        emit ChannelInitiated(channel.channelId, channel.players[0], channel.players[1], channel.channelType);
        PlasmaTurnGame(channelType).eventRequestState(
            channel.channelId,
            initialGameAttributes,
            channel.players[0],
            channel.players[1]
        );
    }

    /**
      * @dev Allows a player respond to a channel creation, funding it.
      *      the winner of it to be able to reclaim it, using within it any plasma tokens deposited on rootChain.
      * @notice Appends ExitData to exits, sets the fundedTimestamp for the channel
      * @notice Sets channel's state to FUNDED
      * @notice Emits ChannelFunded event
      * @param channelId   Unique identifier of the channel
      * @param initialGameAttributes The encoded initial state to be decoded by the channelType
      * @param exitData     The encoded exitData to be decoded by the channelType of the plasma tokens being used by
      *                     the opponent.
      */
    function fundChannel(
        uint channelId,
        bytes calldata initialGameAttributes,
        bytes calldata exitData
    ) external payable channelExists(channelId) {

        FMChannel storage channel = channels[channelId];

        require(channel.state == ChannelState.INITIATED, "Channel is already funded");
        require(channel.players[1] == msg.sender, "Sender is not participant of this channel");
        require(channel.stake == msg.value, "Payment must be equal to channel stake");
        require(channel.initialArgumentsHash == keccak256(initialGameAttributes), "Initial state does not match");
        channel.state = ChannelState.FUNDED;
        channel.fundedTimestamp = block.timestamp;
        RootChain.Exit[] memory exitOpponent = PlasmaTurnGame(channel.channelType)
            .validateStartState(initialGameAttributes, channel.players, 1, exitData);
        for(uint i; i<exitOpponent.length; i++) {
            exits[channel.channelId].push(exitOpponent[i]);
        }
        emit ChannelFunded(channel.channelId, channel.players[0], channel.players[1], channel.channelType, initialGameAttributes);
        PlasmaTurnGame(channel.channelType).eventStartState(channelId, initialGameAttributes, channel.players[0], channel.players[1]);
    }

    /**
      * @dev Allows a creator of a channel to close if it is unfunded and retrieve the stakes.
      * @notice Sets channel's state to CLOSED
      * @notice Emits ChannelConcluded event
      * @param channelId   Unique identifier of the channel
      */
    function closeUnfundedChannel(uint channelId) external channelExists(channelId) {
        FMChannel storage channel = channels[channelId];

        require(channel.state == ChannelState.INITIATED, "Channel is already funded");
        require(channel.players[0] == msg.sender, "Sender is not creator of this channel");

        channel.state = ChannelState.CLOSED;

        funds[msg.sender] = funds[msg.sender] + channel.stake;
        emit ChannelConcluded(channelId, channel.players[0], channel.players[1], channel.channelType);
        delete channels[channelId];
        delete challenges[channelId];
        delete exits[channelId];
    }

    /**
     * @dev Allows conclusion of a channel whether if there is an expired challenge or by providing the last states
     * @notice Sets channel's state to CLOSED. Stakes are added to the winner.
     * @notice Emits ChannelConcluded event
     * @param channelId  Unique identifier of the channel
     * @param prevState  State previous to last state. Ignored if an expired challenge is present.
     * @param lastState  Last State, which must be a valid transition from prevState and also validate as a final state.
     *                   Ignored if an expired challenge is present
     * @param signatures The signatures (array of size 2) corresponding to prevState and lastState in that order.
     *                   Ignored if an expired challenge is present
     */
    function conclude(
        uint channelId,
        State.StateStruct memory prevState,
        State.StateStruct memory lastState,
        bytes[] memory signatures
    ) public channelExists(channelId) isFunded(channelId) {
        FMChannel storage channel = channels[channelId];

        if(!channel.expiredChallengePresent()) {
            channel.conclude(prevState, lastState, signatures);
        }

        //should never fail
        require(channel.expiredChallengePresent(), "Winner not correctly decided");

        channel.state = ChannelState.CLOSED;
        funds[channel.forceMoveChallenge.winner] += channel.stake * 2;
        emit ChannelConcluded(channelId, channel.players[0], channel.players[1], channel.channelType);
        delete channels[channelId];
        delete challenges[channelId];
        delete exits[channelId];
    }

    /**
    * @dev Allows an address to extract the funds locked in this contract
    */
    function withdraw() public {
        require(funds[msg.sender] > 0, "Sender has no funds");
        uint value = funds[msg.sender];
        funds[msg.sender] = 0;
        msg.sender.transfer(value);
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////            Force Moves
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Allows the creation of a forceMove Challenge for the first move in a channel.
     * @notice Modifies the channel's forceMoveChallenge if there isn't any
     * @param channelId  Unique identifier of the channel
     * @param initialState The initial state of the channel. Must comply with the initialArgumentsHash of the channel.
     *                     Will be the starting point to validate the forceMove response
     */
    function forceFirstMove(
        uint channelId,
        State.StateStruct memory initialState
    ) public channelExists(channelId) isAllowed(channelId) {

        channels[channelId].forceFirstMove(initialState, msg.sender);
    }

    /**
     * @dev Allows the creation of a forceMove Challenge for the any move in a channel.
     * @notice Modifies the channel's forceMoveChallenge if there isn't any.
     * @notice Emits ForceMoveRequested event
     * @notice Either the fromState or toState must be signed one by each of the channel's participants to be a valid
     *         transition, so it is ok to assume both parties agreed on these states.
     * @param channelId  Unique identifier of the channel
     * @param fromState   The previous to current state of the channel
     * @param toState     The current state of the channel. Must be a valid transition from fromState
     * @param signatures  The signatures (array of size 2) corresponding to fromState and toState in that order
     */
    function forceMove(
        uint channelId,
        State.StateStruct memory fromState,
        State.StateStruct memory toState,
        bytes[] memory signatures
    ) public channelExists(channelId) isAllowed(channelId) {

        channels[channelId].forceMove(fromState, toState, msg.sender, signatures);
        emit ForceMoveRequested(channelId, toState);
    }

    /**
     * @dev Allows the response of an active forceMove Challenge.
     * @notice Removes the channel's forceMoveChallenge if there is any.
     * @notice Emits ForceMoveResponded event
     * @param channelId  Unique identifier of the channel
     * @param nextState   The next state of the channel. Must be a valid transition from the challenge's state.
     * @param signature   The signature corresponding to nextState
     */
    function respondWithMove(
        uint channelId,
        State.StateStruct memory nextState,
        bytes memory signature
    ) public channelExists(channelId) {

        channels[channelId].respondWithMove(nextState, signature);
        emit ForceMoveResponded(channelId, nextState, signature);
    }

    /**
     * @dev Allows the response of an active forceMove Challenge by canceling with a different state signed by the
     *      challenge's issuer. Then proceeds to create a challenge for the alternativeState.
     * @notice Changes the channel's forceMoveChallenge if there is any.
     * @notice Emits ForceMoveResponded event
     * @notice Emits ForceMoveRequested event
     * @param channelId  Unique identifier of the channel
     * @param alternativeState  The state replacing the challenge's state. Must have the same turnNum as it,
     *                          and thus, be signed by the same person.
     * @param nextState         The next state of the channel. Must be a valid transition from the alternativeState.
     * @param signatures        The signatures (array of size 2) corresponding to alternativeState and nextState in that order
     */
    function alternativeRespondWithMove(
        uint channelId,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures
    ) public channelExists(channelId) isAllowed(channelId) {

        channels[channelId].alternativeRespondWithMove(alternativeState, nextState, msg.sender, signatures);
        emit ForceMoveResponded(channelId, nextState, signatures[1]);
        emit ForceMoveRequested(channelId, nextState);
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////            Plasma Challenges
    //////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Allows a user to challenge a funded channel's exit, by providing a direct spend, in order to prevent the
     *      use of unauthorized tokens.
     * @notice Emits ChannelChallenged event
     * @notice Sets channel's state to CHALLENGED
     * @param channelId   Unique identifier of the channel
     * @param index       Index corresponding to the exit's index to be challenged
     * @param txBytes     RLP encoded bytes of the transaction to make a Challenge After. See CheckAfter for conditions.
     * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
     * @param signature   Signature of the txBytes proving the validity of it.
     * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof
     */
    function challengeAfter(
        uint channelId,
        uint index,
        bytes calldata txBytes,
        bytes calldata proof,
        bytes calldata signature,
        uint256 blockNumber)
    external channelExists(channelId) isFunded(channelId) {
        checkAfter(exits[channelId][index], txBytes, proof, signature, blockNumber);

        FMChannel storage channel = channels[channelId];
        channel.state = ChannelState.CHALLENGED;
        funds[msg.sender] += channel.stake * 2;
        emit ChannelChallenged(channelId, index, channel.players[0], channel.players[1]);
        delete channels[channelId];
        delete challenges[channelId];
        delete exits[channelId];
    }

    /**
     * @dev Checks a transaction to be a direct spend from an Exit
     * @param exit        RootChain.Exit exit to be challenged
     * @param txBytes     RLP encoded bytes of the transaction to make a Challenge After. Should be a direct spend.
     *                     Has to be the same slot, signed by the same owner and its' prevBlock equal to exit's exitBlock
     * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
     * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof. Must be greater to
     *                    exit.exitBlock.
     */
    function checkAfter(
        RootChain.Exit memory exit,
        bytes memory txBytes,
        bytes memory proof,
        bytes memory signature,
        uint blockNumber
    ) private view {

        require(exit.exitBlock < blockNumber, "Tx should be after the exitBlock");
        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.hash.ecverify(signature, exit.owner), "Invalid signature");
        require(txData.slot == exit.slot, "Tx is referencing another slot");
        require(txData.prevBlock == exit.exitBlock, "Not a direct spend");
    }

    /**
     * @dev Allows a user to challenge a funded channel's exit, by providing a previous double spend, in order to prevent the
     *      use of unauthorized tokens.
     * @notice Emits ChannelChallenged event
     * @notice Sets channel's state to CHALLENGED
     * @param channelId   Unique identifier of the channel
     * @param index       Index corresponding to the exit's index to be challenged
     * @param txBytes     RLP encoded bytes of the transaction to make a Challenge Between. See CheckBetween for conditions.
     * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
     * @param signature   Signature of the txBytes proving the validity of it.
     * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof
     */
    function challengeBetween(
        uint channelId,
        uint index,
        bytes calldata txBytes,
        bytes calldata proof,
        bytes calldata signature,
        uint256 blockNumber)
    external channelExists(channelId) isFunded(channelId) {
        checkBetween(exits[channelId][index], txBytes, proof, signature, blockNumber);

        FMChannel storage channel = channels[channelId];
        channel.state = ChannelState.CHALLENGED;
        funds[msg.sender] += channel.stake * 2;
        emit ChannelChallenged(channelId, index, channel.players[0], channel.players[1]);
        delete channels[channelId];
        delete challenges[channelId];
        delete exits[channelId];
    }

    /**
     * @dev Checks a transaction to be a previous double spend from an Exit
     * @param exit        RootChain.Exit exit to be challenged
     * @param txBytes     RLP encoded bytes of the transaction to make a Challenge Between. Should be a direct spend of
     *                    the exit.prevBlock. Has to be the same slot, signed by the same owner and the blockNumber
     *                    Should be before exit.exitBlock.
     * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
     * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof. Must be between exit.prevBlock
     *                    and exit.exitBlock.
     */
    function checkBetween(
        RootChain.Exit memory exit,
        bytes memory txBytes,
        bytes memory proof,
        bytes memory signature,
        uint blockNumber
    ) private view {

        require(exit.exitBlock > blockNumber && exit.prevBlock < blockNumber,
            "Tx should be between the exit's blocks"
        );

        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.hash.ecverify(signature, exit.prevOwner), "Invalid signature");
        require(txData.slot == exit.slot, "Tx is referencing another slot");
    }

    /**
     * @dev Allows a user to create a Plasma Challenge targeting a funded channel's exit in order to prevent the use of
     *       unauthorized tokens. A plasma challenge is any previous transaction of the token that must be proved invalid
     *       by a direct spend of it.
     * @notice Pushes a ChallengeLib.Challenge to challenges
     * @notice Emits ChallengeRequest event
     * @notice Sets channel's state to SUSPENDED
     * @notice A bond must be locked to prevent unlawful challenges. If the challenge is not answered, the bond is returned.
     * @param channelId   Unique identifier of the channel
     * @param index       Index corresponding to the exit's index to be challenged
     * @param txBytes     RLP encoded bytes of the transaction to make a Challenge Before. See CheckBefore for conditions.
     * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
     * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof
     */
    function challengeBefore(
        uint channelId,
        uint index,
        bytes calldata txBytes,
        bytes calldata proof,
        uint256 blockNumber
    ) external payable channelExists(channelId) isChallengeable(channelId) Bonded {

        require(block.timestamp <= channels[channelId].fundedTimestamp + CHALLENGE_PERIOD, "Challenge window is over");
        checkBefore(exits[channelId][index], txBytes, proof, blockNumber);
        bytes32 txHash = txBytes.getHash();
        require(!challenges[channelId].contains(txHash), "Transaction used for challenge already");

        // Need to save the exiting transaction's owner, to verify
        // that the response is valid
        challenges[channelId].push(
            ChallengeLib.Challenge({
            exitor: exits[channelId][index].owner,
            owner:  txBytes.getOwner(),
            challenger: msg.sender,
            txHash: txHash,
            challengingBlockNumber: blockNumber
            })
        );

        FMChannel storage channel = channels[channelId];
        channel.state = ChannelState.SUSPENDED;
        emit ChallengeRequest(channelId, index, txHash, channel.players[0], channel.players[1], msg.sender);
    }

    /**
     * @dev Checks a transaction against an exit for a Challenge Before
     * @param exit        RootChain.Exit exit to be challenged
     * @param txBytes     RLP encoded bytes of the transaction to make a Challenge Before.
     * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
     * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof. Must be previous to
     *                    exit.prevBlock.
     */
    function checkBefore(
        RootChain.Exit memory exit,
        bytes memory txBytes,
        bytes memory proof,
        uint blockNumber
    ) private view {
        require(blockNumber <= exit.prevBlock, "Tx should be before the exit's parent block");
        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.slot == exit.slot, "Tx is referencing another slot");
    }

    /**
     * @dev Allows a user to respond to a Plasma Challenge targeting a funded channel's exit. For validity go to CheckResponse
     * @notice Removes a ChallengeLib.Challenge to challenges
     * @notice Emits ChallengeResponded event
     * @notice Sets channel's state to FUNDED if no more challenges are left
     * @notice The bond is given to the responder.
     * @param channelId             Unique identifier of the channel
     * @param index                 Index corresponding to the exit's index to be challenged
     * @param challengingTxHash     Hash of the transaction being challenged with.
     * @param respondingBlockNumber BlockNumber of the respondingTransaction to be checked for the inclusion proof.
     * @param respondingTransaction Transaction signed by the challengingTxHash owner showing a spent
     * @param proof                 Bytes needed for the proof of inclusion of respondingTransaction in the Plasma block
     * @param signature             Signature of the respondingTransaction to prove its validity
     */
    function respondChallengeBefore(
        uint channelId,
        uint index,
        bytes32 challengingTxHash,
        uint256 respondingBlockNumber,
        bytes calldata respondingTransaction,
        bytes calldata proof,
        bytes calldata signature
    ) external channelExists(channelId) isSuspended(channelId) {

        // Check that the transaction being challenged exists
        ChallengeLib.Challenge[] storage cChallenges = challenges[channelId];
        require(cChallenges.contains(challengingTxHash), "Responding to non existing challenge");
        // Get index of challenge in the challenges array
        uint256 cIndex = uint256(cChallenges.indexOf(challengingTxHash));
        uint _index = index;
        uint _channelId = channelId;
        uint _blockNumber = respondingBlockNumber;
        bytes memory _respondingTransaction = respondingTransaction;
        bytes memory _proof = proof;
        bytes memory _signature = signature;
        RootChain.Exit memory exit = exits[_channelId][_index];
        ChallengeLib.Challenge memory challenge = cChallenges[cIndex];
        checkResponse(
            exit,
            challenge,
            _blockNumber,
            _respondingTransaction,
            _signature,
            _proof
        );

        funds[msg.sender] += CHALLENGE_BOND;
        FMChannel storage channel = channels[_channelId];
        cChallenges.removeAt(_index);

        if(cChallenges.length == 0) {
            channel.state = ChannelState.FUNDED;
        }

        emit ChallengeResponded(_channelId, _index, challenge.txHash, channel.players[0], channel.players[1], challenge.challenger);
    }

   /**
    * @dev Checks a Plasma Challenge's response against an exit.
    * @param exit        RootChain.Exit exit to be challenged
    * @param challenge   ChallengeLib.Challenge challenge to respond to
    * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof. Should be a future spend of
    *                    the challenge.challengingBlockNumber but before the exit.exitBlock. Has to be the same slot,
    *                    signed by the same owner.
    * @param txBytes     RLP encoded bytes of the transaction to proof the spending of the challenge. Must
    * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
    * @param signature   Signature of the txBytes to prove its validity. Must be signed by the challenged owner
    */
    function checkResponse(
        RootChain.Exit memory exit,
        ChallengeLib.Challenge memory challenge,
        uint256 blockNumber,
        bytes memory txBytes,
        bytes memory signature,
        bytes memory proof
    ) private view {

        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.hash.ecverify(signature, challenge.owner), "Invalid signature");
        require(txData.slot == exit.slot, "Tx is referencing another slot");
        require(blockNumber > challenge.challengingBlockNumber, "BlockNumber must be after the chalenge");
        require(blockNumber <= exit.exitBlock, "Cannot respond with a tx after the exit");
    }

    /**
     * @dev Allows a user to close and unanswered channel after a Challenge Before was made
     * @notice Removes a ChallengeLib.Challenge to challenges
     * @notice Emits ChannelChallenged event
     * @notice Sets channel's state to CHALLENGED
     * @notice The bond is returned to the challengers, with the stakes of the channel to the first valid one.
     * @param channelId             Unique identifier of the channel
     */
    function closeChallengedChannel(
        uint channelId
    ) external channelExists(channelId) isSuspended(channelId) {
        FMChannel storage channel = channels[channelId];
        require(block.timestamp >= channel.fundedTimestamp + CHALLENGE_RESPOND_PERIOD, "Challenge respond window isnt over");

        ChallengeLib.Challenge[] memory channelChallenges = challenges[channelId];

        bool playerChallenged = false;
        bool opponentChallenged = false;

        for(uint i=0; i<channelChallenges.length; i++) {
            if(!playerChallenged && channelChallenges[i].exitor == channel.players[0]) {
                playerChallenged = true;
                funds[channelChallenges[i].challenger] += channel.stake;
            } else if(!opponentChallenged && channelChallenges[i].exitor == channel.players[1]) {
                funds[channelChallenges[i].challenger] += channel.stake;
                opponentChallenged = true;
            }
            funds[channelChallenges[i].challenger] += CHALLENGE_BOND;
        }

        channel.state = ChannelState.CHALLENGED;
        if(!playerChallenged) {
            funds[channel.players[0]] += channel.stake;
        }

        if(!opponentChallenged) {
            funds[channel.players[1]] += channel.stake;
        }

        emit ChannelChallenged(channelId, 0, channel.players[0], channel.players[1]);
        delete channels[channelId];
        delete challenges[channelId];
        delete exits[channelId];
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////            Getters
    //////////////////////////////////////////////////////////////////////////////////

    function getFunds(address user) external view returns (uint) {
        return funds[user];
    }

    function getChannel(uint channelId) external view returns (FMChannel memory) {
        return channels[channelId];
    }

    function getExit(uint channelId, uint index) external view returns (RootChain.Exit memory) {
        return exits[channelId][index];
    }

    function getChallenge(uint channelId, bytes32 txHash) external view returns (ChallengeLib.Challenge memory) {

        uint256 index = uint256(challenges[channelId].indexOf(txHash));
        return challenges[channelId][index];
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////            Modifiers
    //////////////////////////////////////////////////////////////////////////////////

    modifier Payment(uint stake) {
        require(stake >= MINIMAL_BET,"Stake must be greater than minimal bet");
        require(stake == msg.value, "Invalid Payment amount");
        _;
    }

    modifier Bonded() {
        require(CHALLENGE_BOND == msg.value, "Challenge Bond must be provided");
        _;
    }

    modifier channelExists(uint channelId) {
        require(channels[channelId].channelId > 0, "Channel has not yet been created");
        _;
    }

    modifier isFunded(uint channelId) {
        require(channels[channelId].state  == ChannelState.FUNDED, "Channel must be funded (maybe there is a challenge)");
        _;
    }

    modifier isSuspended(uint channelId) {
        require(channels[channelId].state  == ChannelState.SUSPENDED, "Channel must be suspended");
        _;
    }

    modifier isChallengeable(uint channelId) {
        require(channels[channelId].state  == ChannelState.SUSPENDED
        || channels[channelId].state  == ChannelState.FUNDED, "Channel must be funded or suspended");
        _;
    }

    modifier isAllowed(uint channelId) {
        require(
            channels[channelId].players[0] == msg.sender || channels[channelId].players[1] == msg.sender,
                "The sender is not involved in the channel"
        );
        _;
    }

}
