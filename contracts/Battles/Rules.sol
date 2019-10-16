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

    function validateStartState(
        State.StateStruct memory state,
        address player,
        address opponent,
        bytes32 initialArgumentsHash
    ) internal pure {
       require(state.turnNum == 0, "First turn must be 0");
       require(state.participants[0] == player, "State player is incorrect");
       require(state.participants[1] == opponent, "State opponent is incorrect");
       require(initialArgumentsHash == keccak256(state.gameAttributes), "Initial states does not match");
    }
    
    function validateTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal pure {
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
    ) internal pure {
        fromState.validateGameTransition(toState);
    }

    function validateSignedTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState,
        bytes[] memory signatures
    ) internal pure {
        // states must be signed by the appropriate participant
        fromState.requireSignature(signatures[0]);
        toState.requireSignature(signatures[1]);

        return validateTransition(fromState, toState);
    }

    function validateRefute(
        State.StateStruct memory challengeState,
        State.StateStruct memory refutationState,
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
        refutationState.requireSignature(signature);
    }

    function validateRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory nextState,
        bytes memory signature
    ) internal pure {
        // check that the challengee's signature matches
        nextState.requireSignature(signature);
        validateTransition(challengeState, nextState);
    }

    function validateAlternativeRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures
    ) internal pure {

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

        validateTransition(alternativeState, nextState);
    }
}