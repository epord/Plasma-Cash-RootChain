pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "./Adjudicator.sol";
import "./Rules.sol";
import "./State.sol";
import "openzeppelin-solidity/contracts/drafts/Counters.sol";
import "../Libraries/ChallengeLib.sol";
import "../Libraries/ECVerify.sol";
import "./PlasmaTurnGame.sol";


//TODO add global timeout for channel
//Plasma Channel Manager
contract PlasmaCM {
    //events
    event ChannelInitiated(uint channelId, address indexed creator, address indexed opponent, address channelType);
    event ChannelFunded(uint channelId, address indexed creator, address indexed opponent, address channelType);

    //events

    using Adjudicators for FMChannel;
    using Counters for Counters.Counter;
    using ECVerify for bytes32;
    using State for State.StateStruct;

    enum ChannelState { INITIATED, FUNDED, SUSPENDED, CLOSED, WITHDRAWN }

    //Force Move Channel
    struct FMChannel {
        uint256 channelId;
        address channelType;
        uint256 stake;
        address[2] players;
        bytes32 initialArgumentsHash;
        ChannelState state;
        Rules.Challenge forceMoveChallenge;
        ChallengeLib.Challenge plasmaChallenge;
    }

    mapping (uint => FMChannel) channels;

    Counters.Counter channelCounter;

    uint256 constant DEPOSIT_AMOUNT = 0.1 ether;
    mapping (address => Counters.Counter) openChannels;
    mapping (address => bool) deposited;

    function () external payable {
        revert("Please send funds using the FundChannel or makeDeposit method");
    }

    //TODO close unfunded channel
    function initiateChannel(
        address channelType,
        address opponent,
        uint stake,
        bytes memory initialGameAttributes
    ) public payable Payment(stake) hasDeposit {

        ((PlasmaTurnGame)(channelType)).validateStartState(initialGameAttributes);
        channelCounter.increment();

        uint channelId = channelCounter.current();

        address[2] memory addresses;
        addresses[0] = msg.sender;
        addresses[1] = opponent;

        openChannels[msg.sender].increment();

        Rules.Challenge memory rchallenge;
        ChallengeLib.Challenge memory cchallenge;

        channels[channelId] = FMChannel(
            channelId,
            channelType,
            stake,
            addresses,
            keccak256(initialGameAttributes),
            ChannelState.INITIATED,
            rchallenge,
            cchallenge
        );


        emit ChannelInitiated(channelId, msg.sender, opponent, channelType);
    }

    function fundChannel(
        uint channelId,
        bytes memory initialGameAttributes
    ) public payable channelExists(channelId) hasDeposit {
        FMChannel storage channel = channels[channelId];

        require(channel.state == ChannelState.INITIATED, "Channel is already funded");
        require(channel.players[1] == msg.sender, "Sender is not participant of this channel");
        require(channel.stake == msg.value, "Payment must be equal to channel stake");
        require(channel.initialArgumentsHash == keccak256(abi.encode(initialGameAttributes)), "Initial state does not match");
        channel.state = ChannelState.FUNDED;

        openChannels[msg.sender].increment();

        //TODO emit
        emit ChannelFunded(channel.channelId, channel.players[0], channel.players[1], channel.channelType);
        ((PlasmaTurnGame)(channel.channelType)).eventStartState(initialGameAttributes, channel.players[0], channel.players[1]);
    }

    function makeDeposit() external payable Payment(DEPOSIT_AMOUNT) {
        require(!deposited[msg.sender], "Sender already did a deposit");
        deposited[msg.sender] = true;
    }

    function retrievedDeposit() external payable hasDeposit {
        require(openChannels[msg.sender].current() == 0, "Sender has an open channel");
        deposited[msg.sender] = false;

        msg.sender.transfer(DEPOSIT_AMOUNT);
    }

    function forceFirstMove(
        uint channelId,
        State.StateStruct memory initialState) public channelExists(channelId) hasDeposit {
        channels[channelId].forceFirstMove(initialState, msg.sender);
    }

    function forceMove(
        uint channelId,
        State.StateStruct memory fromState,
        State.StateStruct memory nextState,
        bytes[] memory signatures)
    public channelExists(channelId) hasDeposit {

        channels[channelId].forceMove(fromState, nextState, msg.sender, signatures);
    }

    function respondWithMove(
        uint channelId,
        State.StateStruct memory nextState,
        bytes memory signature)
    public channelExists(channelId) hasDeposit {

        channels[channelId].respondWithMove(nextState, signature);
    }

    function alternativeRespondWithMove(
        uint channelId,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures)
    public channelExists(channelId) hasDeposit {

        channels[channelId].alternativeRespondWithMove(alternativeState, nextState, signatures);
    }

    function conclude(
        uint channelId,
        State.StateStruct memory prevState,
        State.StateStruct memory lastState,
        bytes[] memory signatures)
        public channelExists(channelId) hasDeposit {

        FMChannel storage channel = channels[channelId];
        channel.conclude(prevState, lastState, signatures);
        channel.state = ChannelState.CLOSED;
        //TODO emit
    }

    function withdraw(uint channelId) external channelExists(channelId) {

        FMChannel storage channel = channels[channelId];
        require(channel.state == ChannelState.CLOSED, "Channel must be closed");
        channel.state = ChannelState.WITHDRAWN;

        openChannels[channel.players[0]].decrement();
        openChannels[channel.players[1]].decrement();

        msg.sender.transfer(channel.stake * 2);
        //TODO emit
    }


    ///
    //CHALLENGES
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

    modifier hasDeposit() {
        require(deposited[msg.sender], "You must make a deposit to use the Game Channels");
        _;
    }
}