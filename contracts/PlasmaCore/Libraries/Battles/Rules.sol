pragma solidity ^0.5.12;
pragma experimental ABIEncoderV2;

import "./State.sol";

library Rules {
    using State for State.StateStruct;

    struct Challenge {
        State.StateStruct state;
        uint32 expirationTime;
        address winner;
    }

    function validateStartState(
        State.StateStruct memory state,
        address[2] memory players,
        bytes32 initialArgumentsHash
    ) internal pure {
        require(state.turnNum == 0, "First turn must be 0");
        require(state.participants[0] == players[0], "State player is incorrect");
        require(state.participants[1] == players[1], "State opponent is incorrect");
        require(initialArgumentsHash == keccak256(state.gameAttributes), "Initial states does not match");
    }

    function validateTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal view {
        require(
            toState.channelId == fromState.channelId,
            "Invalid transition: channelId must match on toState"
        );
        require(
            toState.turnNum == fromState.turnNum + 1,
            "Invalid transition: turnNum must increase by 1"
        );

        require(
            toState.channelType == fromState.channelType,
            "ChannelType must remain the same"
        );

        require(
            toState.participants[0] == fromState.participants[0]
            && toState.participants[1] == fromState.participants[1],
            "Players must remain the same"
        );

        fromState.validateGameTransition(toState);
    }


    function validGameTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal view {
        fromState.validateGameTransition(toState);
    }

    function validateSignedTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState,
        address[2] memory publicKeys,
        bytes[] memory signatures
    ) internal view {
        // states must be signed by the appropriate participant
        fromState.requireSignature(signatures[0], publicKeys);
        toState.requireSignature(signatures[1], publicKeys);

        return validateTransition(fromState, toState);
    }

    function validateRefute(
        State.StateStruct memory challengeState,
        State.StateStruct memory refutationState,
        address[2] memory publicKeys,
        bytes memory signature
    ) internal pure {
        require(
            refutationState.turnNum > challengeState.turnNum,
            "the refutationState must have a higher nonce"
        );
        require(
            refutationState.mover() == challengeState.mover(),
            "refutationState must have same mover as challengeState"
        );
        // ... and be signed (by that mover)
        refutationState.requireSignature(signature, publicKeys);
    }

    function validateRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory nextState,
        address[2] memory publicKeys,
        bytes memory signature
    ) internal view {
        // check that the challengee's signature matches
        nextState.requireSignature(signature, publicKeys);
        validateTransition(challengeState, nextState);
    }

    function validateAlternativeRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        address[2] memory publicKeys,
        bytes[] memory signatures
    ) internal view {

        // checking the alternative state:
        require(
            challengeState.channelId == alternativeState.channelId,
            "alternativeState must have the right channel"
        );

        require(
            challengeState.turnNum == alternativeState.turnNum,
            "alternativeState must have the same nonce as the challenge state"
        );

        // .. it must be signed (by the challenger)
        alternativeState.requireSignature(signatures[0], publicKeys);

        // checking the nextState:
        // .. it must be signed (my the challengee)
        nextState.requireSignature(signatures[1], publicKeys);

        validateTransition(alternativeState, nextState);
    }
}