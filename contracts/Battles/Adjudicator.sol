pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "./State.sol";
import "./Rules.sol";
import "./PlasmaTurnGame.sol";
import "./PlasmaChannelManager.sol";


library Adjudicators {

    using State for State.StateStruct;
    using Adjudicators for PlasmaCM.FMChannel;

    uint constant CHALLENGE_DURATION = 10 * 1 minutes;

    function forceFirstMove(
        PlasmaCM.FMChannel storage channel,
        State.StateStruct memory initialState,
        address issuer
    )
    internal
    withoutCurrentChallenge(channel)
    whenState(channel, PlasmaCM.ChannelState.FUNDED)
    matchId(channel, initialState)
    {
        require(channel.initialStateHash == keccak256(abi.encode(initialState)), "Initial states does not match");
        createChallenge(channel, uint32(now + CHALLENGE_DURATION), initialState, issuer);
    }

    function forceMove(
        PlasmaCM.FMChannel storage channel,
        State.StateStruct memory fromState,
        State.StateStruct memory toState,
        address issuer,
        bytes[] memory signatures
    )
    internal
    withoutCurrentChallenge(channel)
    whenState(channel, PlasmaCM.ChannelState.FUNDED)
    matchId(channel, fromState)
    {
        Rules.validateSignedTransition(fromState, toState, signatures);
        createChallenge(channel, uint32(now + CHALLENGE_DURATION), toState, issuer);
    }

    //Respond is used to cancel your opponent's challenge
    function respondWithMove(
        PlasmaCM.FMChannel storage channel,
        State.StateStruct memory nextState,
        bytes memory signature)
    internal
    withActiveChallenge(channel)
    whenState(channel, PlasmaCM.ChannelState.FUNDED)
    {
        nextState.requireSignature(signature);
        Rules.validateTransition(channel.forceMoveChallenge.state, nextState);
        cancelCurrentChallenge(channel);
    }

    function alternativeRespondWithMove(
        PlasmaCM.FMChannel storage channel,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures
    )
    public
    withActiveChallenge(channel)
    whenState(channel, PlasmaCM.ChannelState.FUNDED)
    {
        Rules.validateAlternativeRespondWithMove(channel.forceMoveChallenge.state, alternativeState, nextState, signatures);
        //TODO check if this should create a new challenge
        cancelCurrentChallenge(channel);
    }

    //TODO revise this
    function refute(
        PlasmaCM.FMChannel storage channel,
        State.StateStruct memory refutingState,
        bytes memory signature
    )
    public
    withActiveChallenge(channel)
    whenState(channel, PlasmaCM.ChannelState.FUNDED)
    {
        Rules.validateRefute(channel.forceMoveChallenge.state, refutingState, signature);
        cancelCurrentChallenge(channel);
    }

    function conclude(
        PlasmaCM.FMChannel storage channel,
        State.StateStruct memory penultimateState,
        State.StateStruct memory ultimateState,
        bytes[] memory signatures
    )
    internal
    withoutActiveChallenge(channel)
    whenState(channel, PlasmaCM.ChannelState.FUNDED)
    matchId(channel, penultimateState)
    {

        Rules.validateSignedTransition(penultimateState, ultimateState, signatures);
        require(ultimateState.isOver(), "Ultimate State must be a final state");

        //Create an expired challenge that acts as the final state
        createChallenge(channel, uint32(now), ultimateState, ultimateState.winner());
    }

    function createChallenge(
        PlasmaCM.FMChannel storage channel,
        uint32 expirationTime,
        State.StateStruct memory state,
        address challengeIssuer)
    private {
        channel.forceMoveChallenge.state = state;
        channel.forceMoveChallenge.expirationTime = expirationTime;

        if(state.isOver()) {
            channel.forceMoveChallenge.winner = state.winner();
        } else {
            channel.forceMoveChallenge.winner = challengeIssuer;
        }
    }

    function cancelCurrentChallenge(PlasmaCM.FMChannel storage channel) private{
        channel.forceMoveChallenge.expirationTime = 0;
    }

    function currentChallengePresent(PlasmaCM.FMChannel storage channel) public view returns (bool) {
        return channel.forceMoveChallenge.expirationTime > 0;
    }

    function activeChallengePresent(PlasmaCM.FMChannel storage channel) public view returns (bool) {
        return (channel.forceMoveChallenge.expirationTime > now);
    }

    function expiredChallengePresent(PlasmaCM.FMChannel storage channel) public view returns (bool) {
        return channel.currentChallengePresent() && !channel.activeChallengePresent();
    }

    // Modifiers
    modifier withCurrentChallenge(PlasmaCM.FMChannel storage channel) {
        require(channel.currentChallengePresent(), "Current challenge must be present");
        _;
    }

    modifier withoutCurrentChallenge(PlasmaCM.FMChannel storage channel) {
        require(!channel.currentChallengePresent(), "current challenge must not be present");
        _;
    }

    modifier withActiveChallenge(PlasmaCM.FMChannel storage channel) {
        require(channel.activeChallengePresent(), "active challenge must be present");
        _;
    }

    modifier withoutActiveChallenge(PlasmaCM.FMChannel storage channel) {
        require(!channel.activeChallengePresent(), "active challenge must be present");
        _;
    }

    modifier whenState(PlasmaCM.FMChannel storage channel, PlasmaCM.ChannelState state) {
        require(channel.state == state, "Incorrect channel state");
        _;
    }

    modifier matchId(PlasmaCM.FMChannel storage channel, State.StateStruct memory state) {
        require(channel.channelId == state.channelId, "Channel's channelId must match the state's channelId");
        _;
    }
}