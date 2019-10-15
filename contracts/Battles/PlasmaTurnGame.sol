pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

contract PlasmaTurnGame {
    function validateStartState(bytes memory /*state*/) public pure {  }
    function validateTurnTransition(bytes memory /*oldstate*/, uint /*oldturnNum*/, bytes memory /*newstate*/) public pure { }
    function winner(bytes memory /*state*/, uint /*turnNum*/, address /*player*/, address /*opponent*/) public pure returns (address) { return address(0); }
    function isOver(bytes memory /*state*/, uint /*turnNum*/) public pure returns (bool) { return false; }
    function mover(bytes memory /*state*/, uint /*turnNum*/, address /*player*/, address /*opponent*/) public pure returns (address) { return address(0); }
    function eventStartState(bytes memory /*state*/, address /*player*/, address /*opponent*/) public {}
}