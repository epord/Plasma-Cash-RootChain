pragma solidity ^0.5.12;
pragma experimental ABIEncoderV2;

import "../ECVerify.sol";
import "../../PlasmaTurnGame.sol";


library State {

    using ECVerify for bytes32;

    struct StateStruct {
        uint256 channelId;
        address channelType;        //Game address
        address[] participants;
        uint256 turnNum;
        bytes gameAttributes;       //Current Game State
    }

    function game(StateStruct memory state) public pure returns (PlasmaTurnGame) {
        return (PlasmaTurnGame)(state.channelType);
    }

    function mover(StateStruct memory state) public pure returns (address) {
        return game(state).mover(state.gameAttributes, state.turnNum, state.participants[0], state.participants[1]);
    }

    function winner(StateStruct memory state) public pure returns (address) {
        return game(state).winner(state.gameAttributes, state.turnNum, state.participants[0], state.participants[1]);
    }

    function isOver(StateStruct memory state) public pure returns (bool) {
        return game(state).isOver(state.gameAttributes, state.turnNum);
    }

    function validateGameTransition(StateStruct memory state, StateStruct memory newState) public view {
        game(state).validateTurnTransition(state.gameAttributes, state.turnNum, newState.gameAttributes);
    }

    //State is signed by mover
    function requireSignature(StateStruct memory state, bytes memory signature, address[2] memory publicKeys) public pure {
        address key = mover(state) == state.participants[0] ? publicKeys[0] : publicKeys[1];
        require(
            keccak256(abi.encodePacked(state.channelId, state.channelType, state.participants, state.turnNum, state.gameAttributes))
                .ecverify(signature, key), "mover must have signed state"
        );
    }
}