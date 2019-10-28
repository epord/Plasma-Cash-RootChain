pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "./Adjudicator.sol";
import "./Rules.sol";
import "./State.sol";
import "openzeppelin-solidity/contracts/drafts/Counters.sol";
import "../Libraries/ChallengeLib.sol";
import "../Libraries/ECVerify.sol";
import "./PlasmaTurnGame.sol";
import "../Core/RootChain.sol";


//Plasma Channel Manager
contract PlasmaCM {
    //events
    event ChannelInitiated(uint channelId, address indexed creator, address indexed opponent, address channelType);
    event ChannelFunded(uint channelId, address indexed creator, address indexed opponent, address channelType, bytes initialState);
    event ChannelConcluded(uint channelId, address indexed creator, address indexed opponent, address channelType);
    event ForceMoveResponded(uint indexed channelId, State.StateStruct nextState, bytes signature);
    //events

    using Adjudicators for FMChannel;
    using Counters for Counters.Counter;
    using ECVerify for bytes32;
    using State for State.StateStruct;
    using Transaction for bytes;
    using ChallengeLib for ChallengeLib.Challenge[];

    enum ChannelState { INITIATED, FUNDED, CLOSED, SUSPENDED }

    //Force Move Channel
    struct FMChannel {
        uint256 channelId;
        address channelType;
        uint256 stake;
        address[2] players;
        bytes32 initialArgumentsHash;
        ChannelState state;
        Rules.Challenge forceMoveChallenge;
    }

    struct Challenge {
        uint index;
        ChallengeLib.Challenge challenge;
    }

    mapping (uint => FMChannel) channels;
    mapping (uint => ChallengeLib.Challenge[]) challenges;
    mapping (uint => RootChain.Exit[]) exits;
    mapping (address => uint) funds;

    Counters.Counter channelCounter;
    RootChain rootChain;

    uint256 constant MINIMAL_BET = 0.01 ether;

    function () external payable {
        revert("Please send funds using the FundChannel or makeDeposit method");
    }

    constructor(RootChain _rootChain) public {
        rootChain = _rootChain;
    }

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
        RootChain.Exit[] memory exitPlayer = ((PlasmaTurnGame)(channelType)).validateStartState(initialGameAttributes, addresses,  exitData);
        for(uint i; i<exitPlayer.length; i++) {
            exits[channelCounter.current()].push(exitPlayer[i]);
        }
        Rules.Challenge memory rchallenge;

        FMChannel memory channel = FMChannel(
            channelCounter.current(),
            channelType,
            stake,
            addresses,
            keccak256(initialGameAttributes),
            ChannelState.INITIATED,
            rchallenge
        );

        channels[channel.channelId] = channel;
        emit ChannelInitiated(channel.channelId, channel.players[0], channel.players[1], channel.channelType);

        ((PlasmaTurnGame)(channelType)).eventRequestState(
            channel.channelId,
            initialGameAttributes,
            channel.players[0],
            channel.players[1]
        );
    }

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
        RootChain.Exit[] memory exitOpponent = ((PlasmaTurnGame)(channel.channelType)).validateStartState(initialGameAttributes, channel.players,  exitData);
        for(uint i; i<exitOpponent.length; i++) {
            exits[channel.channelId].push(exitOpponent[i]);
        }
        emit ChannelFunded(channel.channelId, channel.players[0], channel.players[1], channel.channelType, initialGameAttributes);
        ((PlasmaTurnGame)(channel.channelType)).eventStartState(channelId, initialGameAttributes, channel.players[0], channel.players[1]);
    }

    function closeUnfundedChannel(uint channelId) external channelExists(channelId) {
        FMChannel storage channel = channels[channelId];

        require(channel.state == ChannelState.INITIATED, "Channel is already funded");
        require(channel.players[0] == msg.sender, "Sender is not creator of this channel");

        channel.state = ChannelState.CLOSED;

        funds[msg.sender] = funds[msg.sender] + channel.stake;
        emit ChannelConcluded(channelId, channel.players[0], channel.players[1], channel.channelType);
    }

    function forceFirstMove(
        uint channelId,
        State.StateStruct memory initialState) public channelExists(channelId) isAllowed(channelId) {
        channels[channelId].forceFirstMove(initialState, msg.sender);
    }

    function forceMove(
        uint channelId,
        State.StateStruct memory fromState,
        State.StateStruct memory nextState,
        bytes[] memory signatures)
    public channelExists(channelId) isAllowed(channelId) {
        channels[channelId].forceMove(fromState, nextState, msg.sender, signatures);
    }

    function respondWithMove(
        uint channelId,
        State.StateStruct memory nextState,
        bytes memory signature)
    public channelExists(channelId) {
        FMChannel storage channel = channels[channelId];
        channel.respondWithMove(nextState, signature);
        emit ForceMoveResponded(channelId, nextState, signature);
    }

    function alternativeRespondWithMove(
        uint channelId,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures)
    public channelExists(channelId) {
        channels[channelId].alternativeRespondWithMove(alternativeState, nextState, signatures);
    }

    function conclude(
        uint channelId,
        State.StateStruct memory prevState,
        State.StateStruct memory lastState,
        bytes[] memory signatures)
        public channelExists(channelId) {

        FMChannel storage channel = channels[channelId];
        require(channel.state == ChannelState.FUNDED, "Channel must be funded to conclude it");

        if(!channel.expiredChallengePresent()) {
            channel.conclude(prevState, lastState, signatures);
        }

        //should never fail
        require(channel.expiredChallengePresent(), "Winner not correctly decided");

        channel.state = ChannelState.CLOSED;
        funds[channel.forceMoveChallenge.winner] += channel.stake * 2;
        emit ChannelConcluded(channelId, channel.players[0], channel.players[1], channel.channelType);
    }

    function withdraw() public {
        require(funds[msg.sender] > 0, "Sender has no funds");
        uint value = funds[msg.sender];
        funds[msg.sender] = 0;
        msg.sender.transfer(value);
    }

    function getFunds(address user) external view returns (uint) {
        return funds[user];
    }

    function getChannel(uint channelId) external view returns (FMChannel memory) {
        return channels[channelId];
    }

    ///
    // CHALLENGES
    ///
    function challengeBefore(
        uint channelId,
        uint index,
        bytes calldata txBytes,
        bytes calldata txInclusionProof,
        uint256 blockNumber)
    external
    {
        checkBefore(exits[channelId][index], txBytes, txInclusionProof, blockNumber);
        bytes32 txHash = txBytes.getHash();
        require(!challenges[channelId].contains(txHash), "Transaction used for challenge already");

        // Need to save the exiting transaction's owner, to verify
        // that the response is valid
        challenges[channelId].push(
            ChallengeLib.Challenge({
                owner:  txBytes.getOwner(),
                challenger: msg.sender,
                txHash: txHash,
                challengingBlockNumber: blockNumber
            })
        );
    }

    function checkBefore(RootChain.Exit memory exit, bytes memory txBytes, bytes memory proof, uint blockNumber)
    private
    view
    {
        require(blockNumber <= exit.prevBlock, "Tx should be before the exit's parent block");
        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.slot == exit.slot, "Tx is referencing another slot");
    }

    function challengeAfter(
        uint channelId,
        uint index,
        bytes calldata challengingTransaction,
        bytes calldata proof,
        bytes calldata signature,
        uint256 challengingBlockNumber)
    external
    {
        checkAfter(exits[channelId][index], challengingTransaction, proof, signature, challengingBlockNumber);
    }

    function checkAfter(
        RootChain.Exit memory exit,
        bytes memory txBytes,
        bytes memory proof,
        bytes memory signature,
        uint blockNumber) private view {
        require(exit.exitBlock < blockNumber, "Tx should be after the exitBlock");
        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.hash.ecverify(signature, exit.owner), "Invalid signature");
        require(txData.slot == exit.slot, "Tx is referencing another slot");
        require(txData.prevBlock == exit.exitBlock, "Not a direct spend");
    }

    function challengeBetween(
        uint channelId,
        uint index,
        bytes calldata challengingTransaction,
        bytes calldata proof,
        bytes calldata signature,
        uint256 challengingBlockNumber)
    external
    {
        checkBetween(exits[channelId][index], challengingTransaction, proof, signature, challengingBlockNumber);
//        applyPenalties(slot);
    }

    function checkBetween(
        RootChain.Exit memory exit,
        bytes memory txBytes,
        bytes memory proof,
        bytes memory signature,
        uint blockNumber)
    private
    view
    {
        require(exit.exitBlock > blockNumber && exit.prevBlock < blockNumber,
            "Tx should be between the exit's blocks"
        );

        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.hash.ecverify(signature, exit.prevOwner), "Invalid signature");
        require(txData.slot == exit.slot, "Tx is referencing another slot");
    }

    function respondChallengeBefore(
        uint channelId,
        uint index,
        bytes32 challengingTxHash,
        uint256 respondingBlockNumber,
        bytes calldata respondingTransaction,
        bytes calldata proof,
        bytes calldata signature)
    external
    {
        // Check that the transaction being challenged exists
        require(challenges[channelId].contains(challengingTxHash), "Responding to non existing challenge");

        // Get index of challenge in the challenges array
        uint256 cIndex = uint256(challenges[channelId].indexOf(challengingTxHash));
        checkResponse(
            exits[channelId][index],
            challenges[channelId][cIndex],
            respondingBlockNumber,
            respondingTransaction,
            signature,
            proof);

        // If the exit was actually challenged and responded, penalize the challenger and award the responder
//        slashBond(challenges[slot][index].challenger, msg.sender);

//        challenges[slot].remove(challengingTxHash);
//        emit RespondedExitChallenge(slot);
    }

    function checkResponse(
        RootChain.Exit memory exit,
        ChallengeLib.Challenge memory challenge,
        uint256 blockNumber,
        bytes memory txBytes,
        bytes memory signature,
        bytes memory proof
    )
    private
    view
    {
        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.hash.ecverify(signature, challenge.owner), "Invalid signature");
        require(txData.slot == exit.slot, "Tx is referencing another slot");
        require(blockNumber > challenge.challengingBlockNumber, "BlockNumber must be after the chalenge");
        require(blockNumber <= exit.exitBlock, "Cannot respond with a tx after the exit");
    }
    ///

    //modifiers
    modifier Payment(uint stake) {
        require(stake > 0,"Stake must be greater than 0");
        require(stake == msg.value, "Invalid Payment amount");
        _;
    }

    modifier channelExists(uint channelId) {
        require(channels[channelId].channelId > 0, "Channel has not yet been created");
        _;
    }

    modifier isAllowed(uint channelId) {
        require(channels[channelId].players[0] == msg.sender || channels[channelId].players[1] == msg.sender, "The sender is not involved in the channel");
        _;
    }

}
