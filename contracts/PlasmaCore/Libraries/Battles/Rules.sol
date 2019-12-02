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
        require(state.turnNum == 0);
        require(state.participants[0] == players[0]);
        require(state.participants[1] == players[1]);
        require(initialArgumentsHash == keccak256(state.gameAttributes));
    }

    function validateTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal view {
        require(
            toState.channelId == fromState.channelId
        );
        require(
            toState.turnNum == fromState.turnNum + 1
        );

        require(
            toState.channelType == fromState.channelType
        );

        require(
            toState.participants[0] == fromState.participants[0]
            && toState.participants[1] == fromState.participants[1]
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

    }
}