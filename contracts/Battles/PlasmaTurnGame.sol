pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import './State.sol';

contract PlasmaTurnGame {
    function validateTransition(State.StateStruct memory oldState, State.StateStruct memory newState) public pure returns (bool) { return false; }
    function isValidStartState(State.StateStruct memory state) public pure returns (bool) { return false; }
    function winner(State.StateStruct memory state) public pure returns (address) { return address(0); }
    function isOver(State.StateStruct memory state) public pure returns (bool) { return false; }
    function mover(State.StateStruct memory state) public pure returns (address) { return address(0); }
    function eventStartState(State.StateStruct memory state) public {}
}