pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "./PlasmaTurnGame.sol";
import "../Libraries/ECVerify.sol";

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
        return game(state).mover(state);
    }

    function winner(StateStruct memory state) public pure returns (address) {
        return game(state).winner(state);
    }

    function isOver(StateStruct memory state) public pure returns (bool) {
        return game(state).isOver(state);
    }

    //State is signed by mover
    function requireSignature(StateStruct memory state, bytes memory signature) public pure {
        require(
            keccak256(abi.encode(state)).ecverify(signature, mover(state)),
            "mover must have signed state"
        );
    }
}