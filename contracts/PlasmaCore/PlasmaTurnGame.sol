pragma solidity ^0.5.12;
pragma experimental ABIEncoderV2;

import "./RootChain.sol";
/**
  * Interface to be implemented by any contract willing to serve as a game for the PlasmaChannelManager.
  * The game must comply with the following restrictions (for the current state of the code):
  *     - Be a 2 player game
  *     - Be a turn-based game
  *     - Each state transition must only depend on the immediate previous state
  *     - Each state transition must be deterministic
  *     - There has to be a final state, which has to be able to be differentiated from any other normal state.
  *       When reaching this state, the channel is allowed to be closed and a winner can be determined. After reaching the
  *       final states, no more transitions are allowed.
  * To also take into account:
  *     - RNG can be achieved by provided hashed salt by both participants
  *     - Concealed moves can be achieve by hashing the move before revealing it
  */
interface PlasmaTurnGame {
    /**
     * @dev Validates whether a provided state can be classified as a valid Starting point for the channel. Also generates
     *      the exitDatas for any plasma token currently being used in this channel.
     * @param state         Serialized state to be validated as a Starting State.
     * @param players       Addresses of the participants of the game
     * @param exitDataIndex (0 or 1) Determine whose tokens should be validated with the exitData. This function will be called twice,
     *                      first with the creator exitData and then with the opponent exitData.
     * @param exitData      Serialized data necessary to generate an exit for any token being used in the channel.
     */
    function validateStartState(bytes calldata state, address[2] calldata players, uint exitDataIndex, bytes calldata exitData)
        external view returns (RootChain.Exit[] memory);

    /**
      * @dev Validates whether a transition of state is valid for this game.
      * @param oldState         Serialized state to be considered as the first part of the transition.
      * @param oldTurnNum       Turn Number for oldState
      * @param newState         Serialized state to be validated as a transition from oldState
      */
    function validateTurnTransition(bytes calldata oldState, uint oldTurnNum, bytes calldata newState) external view;

    /**
      * @dev Given a final state, returns the winner of the state. If the state is not final, is return value is not valid.
      * @param state         Serialized state from which the winner is determined.
      * @param turnNum       Turn Number for state
      * @param player        Address of the creator of the channel
      * @param opponent      Address of the opponent of the channel
      */
    function winner(bytes calldata state, uint turnNum, address player, address opponent) external pure returns (address);

    /**
      * @dev Given a state, determines whether it can be considered as a final state.
      * @param state         Serialized state to be considered as a final state.
      * @param turnNum       Turn Number for state
      */
    function isOver(bytes calldata state, uint turnNum) external pure returns (bool);

    /**
      * @dev Given a state, determines which address should be the one signing the state.
      * @param state         Serialized state.
      * @param turnNum       Turn Number for state
      * @param player        Address of the creator of the channel
      * @param opponent      Address of the opponent of the channel
      */
    function mover(bytes calldata state, uint turnNum, address player, address opponent) external pure returns (address);


    /**
      * @dev Generates an event when a game is requested from a player against the opponent for users to listen
      *      It is also used to listen to Plasma tokens to be able to respond and challenge them.
      * @param gameId        Unique identifier of the game. Usually used the channelId
      * @param state         Serialized state.
      * @param player        Address of the creator of the channel
      * @param opponent      Address of the opponent of the channel
      */
    function eventRequestState(uint gameId, bytes calldata state, address player, address opponent) external;


    /**
      * @dev Generates an event when a game has started, as both players have agreed on an initial state
      *      It is also used to listen to Plasma tokens to be able to respond and challenge them.
      * @param gameId        Unique identifier of the game. Usually used the channelId
      * @param state         Serialized state.
      * @param player        Address of the creator of the channel
      * @param opponent      Address of the opponent of the channel
      */
    function eventStartState(uint gameId, bytes calldata state, address player, address opponent) external;
}