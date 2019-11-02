pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "./State.sol";
import "./Rules.sol";

import "../../Core/Plasma/PlasmaChannelManager.sol";

/**
 * Library Adjudicators for coin deposit logging.
 * Library in charge of validating valid moves for a PlasmaCM.FMChannel and
 *         managing the force moves challenges in it.
 */
library Adjudicators {

    using State for State.StateStruct;

    uint constant CHALLENGE_DURATION = 10 * 1 minutes;

    /**
     * @dev Allows the creation of a forceMove Challenge for the first move in a channel.
     * @notice Modifies the channel's forceMoveChallenge if there isn't any
     * @param channel The FMChannel to force a move in
     * @param initialState The initial state of the channel. Must comply with the initialArgumentsHash of the channel.
                           Will be the starting point to validate the forceMove response
     * @param issuer The address of the forceMove challenge requester
     */
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
        Rules.validateStartState(initialState, channel.players[0], channel.players[1], channel.initialArgumentsHash);
        createChallenge(channel, uint32(now + CHALLENGE_DURATION), initialState, issuer);
    }

    /**
     * @dev Allows the creation of a forceMove Challenge for the any move in a channel.
     * @notice Modifies the channel's forceMoveChallenge if there isn't any.
     * @notice Either the fromState or toState must be signed one by each of the channel's participants to be a valid
               transition, so it is ok to assume both parties agreed on these states.
     * @param channel     The FMChannel to force a move in
     * @param fromState   The previous to current state of the channel
     * @param toState     The current state of the channel. Must be a valid transition from fromState
     * @param issuer      The address of the forceMove challenge requester
     * @param signatures  The signatures (array of size 2) corresponding to fromState and toState in that order
     */
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
        if(signatures[0].length == 0 ) {
            Rules.validateStartState(fromState, channel.players[0], channel.players[1], channel.initialArgumentsHash);
            toState.requireSignature(signatures[1]);
            Rules.validateTransition(fromState, toState);
        } else {
            Rules.validateSignedTransition(fromState, toState, signatures);
        }
        createChallenge(channel, uint32(now + CHALLENGE_DURATION), toState, issuer);
    }

    /**
     * @dev Allows the response of an active forceMove Challenge.
     * @notice Removes the channel's forceMoveChallenge if there is any.
     * @param channel     The FMChannel to force a move in
     * @param nextState   The next state of the channel. Must be a valid transition from the challenge's state.
     * @param signature   The signature corresponding to nextState
     */
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

    /**
     * @dev Allows the response of an active forceMove Challenge by canceling with a different state signed by the
            challenge's issuer. Then proceeds to create a challenge for the alternativeState.
     * @notice Changes the channel's forceMoveChallenge if there is any.
     * @param channel           The FMChannel to force a move in
     * @param alternativeState  The state replacing the challenge's state. Must have the same turnNum as it,
                                and thus, be signed by the same person.
     * @param nextState         The next state of the channel. Must be a valid transition from the alternativeState.
     * @param issuer            The address of the forceMove challenge responder
     * @param signatures        The signatures (array of size 2) corresponding to alternativeState and nextState in that order
     */
    function alternativeRespondWithMove(
        PlasmaCM.FMChannel storage channel,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        address issuer,
        bytes[] memory signatures
    )
    public
    withActiveChallenge(channel)
    whenState(channel, PlasmaCM.ChannelState.FUNDED)
    {
        //AlternativeState will never be the first state since the hash vaidate in the forceMoveChannel
        Rules.validateAlternativeRespondWithMove(channel.forceMoveChallenge.state, alternativeState, nextState, signatures);
        cancelCurrentChallenge(channel);
        createChallenge(channel, uint32(now + CHALLENGE_DURATION), nextState, issuer);
    }

    /**
     * @dev Allows the response of an active forceMove Challenge by refuting the challenge providing a newer state signed
            by the challenger.
     * @notice Removes the channel's forceMoveChallenge if there is any.
     * @param channel        The FMChannel to force a move in
     * @param refutingState  The state refuting the challenge's state. Must have a higher turnNum and be signed by the issuer.
     * @param signature      The signature corresponding to refutingState
     */
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

    /**
     * @dev Allows the conclusion of a channel by providing the last State of it.
     * @notice Creates an expired challenge with the state as the last state and the issuer as the winner.
     * @notice Either the penultimateState or ultimateState must be signed one by each of the channel's participants
               to be a valid transition, so it is ok to assume both parties agreed on these states.
     * @param channel          The FMChannel to force a move in
     * @param penultimateState The previous to last state of the channel
     * @param ultimateState    The last state of the channel. Must be a valid transition from penultimateState
                               and a valid ending state
     * @param signatures       The signatures (array of size 2) corresponding to penultimateState and ultimateState in that order
     */
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
        channel.forceMoveChallenge.state.channelId = 0;
    }

    function currentChallengePresent(PlasmaCM.FMChannel storage channel) public view returns (bool) {
        return channel.forceMoveChallenge.state.channelId > 0;
    }

    function activeChallengePresent(PlasmaCM.FMChannel storage channel) public view returns (bool) {
        return (channel.forceMoveChallenge.expirationTime > now);
    }

    function expiredChallengePresent(PlasmaCM.FMChannel storage channel) public view returns (bool) {
        return currentChallengePresent(channel) && !activeChallengePresent(channel);
    }

    // Modifiers
    modifier withCurrentChallenge(PlasmaCM.FMChannel storage channel) {
        require(currentChallengePresent(channel), "Current challenge must be present");
        _;
    }

    modifier withoutCurrentChallenge(PlasmaCM.FMChannel storage channel) {
        require(!currentChallengePresent(channel), "current challenge must not be present");
        _;
    }

    modifier withActiveChallenge(PlasmaCM.FMChannel storage channel) {
        require(activeChallengePresent(channel), "active challenge must be present");
        _;
    }

    modifier withoutActiveChallenge(PlasmaCM.FMChannel storage channel) {
        require(!activeChallengePresent(channel), "active challenge must not be present");
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