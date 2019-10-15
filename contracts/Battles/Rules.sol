pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "./State.sol";
import "./PlasmaTurnGame.sol";

library Rules {
    using State for State.StateStruct;

    struct Challenge {
        State.StateStruct state;
        uint32 expirationTime;
        address winner;
    }

    function validateTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal pure returns (bool) {
        require(
            toState.channelId == fromState.channelId,
            "Invalid transition: channelId must match on toState"
        );
        require(
            toState.turnNum == fromState.turnNum + 1,
            "Invalid transition: turnNum must increase by 1"
        );

        require(
            validGameTransition(fromState, toState),
            "Invalid transition from Game: transition must be valid"
        );

        return true;
    }


    function validGameTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal pure returns (bool) {
        return PlasmaTurnGame(fromState.channelType).validateTransition(fromState, toState);
    }

    function validateSignedTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState,
        bytes[] memory signatures
    ) internal pure returns (bool) {
        // states must be signed by the appropriate participant
        fromState.requireSignature(signatures[0]);
        toState.requireSignature(signatures[1]);

        return validateTransition(fromState, toState);
    }

    function validateRefute(
        State.StateStruct memory challengeState,
        State.StateStruct memory refutationState,
        bytes memory signature
    ) internal pure returns (bool) {
        require(
            refutationState.turnNum > challengeState.turnNum,
            "the refutationState must have a higher nonce"
        );
        require(
            refutationState.mover() == challengeState.mover(),
            "refutationState must have same mover as challengeState"
        );
        // ... and be signed (by that mover)
        refutationState.requireSignature(signature);

        return true;
    }

    function validateRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory nextState,
        bytes memory signature
    ) internal pure returns (bool) {
        // check that the challengee's signature matches
        nextState.requireSignature(signature);
        validateTransition(challengeState, nextState);
        return true;
    }

    function validateAlternativeRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures
    ) internal pure returns (bool) {

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
        alternativeState.requireSignature(signatures[0]);

        // checking the nextState:
        // .. it must be signed (my the challengee)
        nextState.requireSignature(signatures[1]);
        
        require(
            validateTransition(alternativeState, nextState),
            "it must be a valid transition of the gamestate (from the alternative state)"
        );

        return true;
    }
}