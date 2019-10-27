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

    struct Exit {
        uint64 slot;
        address prevOwner; // previous owner of coin
        address owner;
        uint256 createdAt;
        uint256 prevBlock;
        uint256 exitBlock;
    }

    struct Challenge {
        uint index;
        ChallengeLib.Challenge challenge;
    }

    mapping (uint => FMChannel) channels;
    mapping (uint => Challenge[]) challenges;
    mapping (uint => Exit[]) exits;
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

        Exit[] memory exitPlayer = ((PlasmaTurnGame)(channelType)).validateStartState(initialGameAttributes, exitData);
        for(uint i; i<exitPlayer.length; i++) {
            exits[channelCounter.current()].push(exitPlayer[i]);
        }
        address[2] memory addresses;
        addresses[0] = msg.sender;
        addresses[1] = opponent;

        Rules.Challenge memory rchallenge;
        ChallengeLib.Challenge memory cchallenge;

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
        bytes calldata initialGameAttributes
    ) external payable channelExists(channelId) {
        FMChannel storage channel = channels[channelId];

        require(channel.state == ChannelState.INITIATED, "Channel is already funded");
        require(channel.players[1] == msg.sender, "Sender is not participant of this channel");
        require(channel.stake == msg.value, "Payment must be equal to channel stake");
        require(channel.initialArgumentsHash == keccak256(initialGameAttributes), "Initial state does not match");
        channel.state = ChannelState.FUNDED;

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


    function checkBefore(Exit memory exit, bytes memory txBytes, bytes memory proof, uint blockNumber)
    private
    view
    {
        require(blockNumber <= exit.prevBlock, "Tx should be before the exit's parent block");
        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.slot == exit.slot, "Tx is referencing another slot");
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
