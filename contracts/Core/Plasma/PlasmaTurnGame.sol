pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "./RootChain.sol";

interface PlasmaTurnGame {
    function validateStartState(bytes calldata state, address[2] calldata players, uint exitDataIndex, bytes calldata exitData)
        external view returns (RootChain.Exit[] memory);

    function validateTurnTransition(bytes calldata oldstate, uint oldturnNum, bytes calldata newstate) external view;
    function winner(bytes calldata state, uint turnNum, address player, address opponent) external pure returns (address);
    function isOver(bytes calldata state, uint turnNum) external pure returns (bool);
    function mover(bytes calldata state, uint turnNum, address player, address opponent) external pure returns (address);
    function eventRequestState(uint gameId, bytes calldata state, address player, address opponent) external;
    function eventStartState(uint gameId, bytes calldata state, address player, address opponent) external;
}