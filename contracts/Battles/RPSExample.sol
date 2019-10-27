pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "./PlasmaTurnGame.sol";
import "../Libraries/Transaction/RLPReader.sol";
import "./PlasmaChannelManager.sol";

contract RPSExample is PlasmaTurnGame {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    //Signed Player -> Signed OP        -> Signed Player

    //initialState  + //State 1         + //State even      + //State odd         +  //State ending (odd)
    //GamesToPlay   | //GamesToPlay     | //GamesToPlay     | //GamesToPlay       |  //GamesToPlay == 0
    //ScorePl       | //ScorePl         | //ScorePl         | //ScorePl           |  //ScorePl
    //ScoreOp       | //ScoreOp         | //ScoreOp         | //ScoreOp           |  //ScoreOp
    //              | //HashDecision    | //HashDecision    | //HashDecision  	  |  //HashDecision
    //              |                   | //DecsionPl       | //DecisionPl        |  //DecisionPl
    //              |                   |                   | //DecisionOp        |  //DecisionOp
    //              |                   |                   | //Salt              |  //Salt
    //              |                   |                   | //nextHashDecision  |

    //Rock 0, Paper 1, Scissor 2

    function validateStartState(bytes calldata state, bytes calldata exitData) external view returns (PlasmaCM.Exit[] memory) {
        RLPReader.RLPItem[] memory start = state.toRlpItem().toList();
        require(start.length == 3, "Invalid RLP length");
        require(start[0].toUint()%2 == 1 , "GamesToPlay must greater be odd number");
        require(start[1].toUint() == 0 && start[2].toUint() == 0, "Players must start with a score of 0");
        return new PlasmaCM.Exit[](0);
    }

    function validateTurnTransition(bytes memory oldState, uint turnNum, bytes memory newState) public view {
        if(turnNum == 0) {
            validateInitialTransition(oldState, newState);
        } else if(turnNum%2 == 0) {
            validateEvenToOdd(oldState, newState, isOver(newState, turnNum));
        } else {
            validateOddToEven(oldState, newState, turnNum == 1);
        }
    }

    function validateInitialTransition(bytes memory startState, bytes memory firstTurn) public pure {
        RLPReader.RLPItem[] memory start = startState.toRlpItem().toList();
        RLPReader.RLPItem[] memory first = firstTurn.toRlpItem().toList();

        require(first.length == 4, "Invalid first turn RLP length");
        require(start[0].toUint() == first[0].toUint(), "GamesToPlay should not change on first turn");
        require(first[1].toUint() == 0 && first[2].toUint() == 0, "Score should not change on first turn");
        require(first[3].toUint() != 0, "Invalid hash");
    }

    function validateEvenToOdd(bytes memory evenTurn, bytes memory oddTurn, bool isFinal) private pure {
        RLPReader.RLPItem[] memory even = evenTurn.toRlpItem().toList();
        RLPReader.RLPItem[] memory odd = oddTurn.toRlpItem().toList();

        if(isFinal) {
            require(odd.length == 7, "Invalid ending turn RLP length");
        } else {
            require(odd.length == 8, "Invalid ending turn RLP length");
        }

        uint evenGTP = even[0].toUint();
        uint evenScorePL = even[1].toUint();
        uint evenScoreOP = even[2].toUint();
        bytes32 evenHashDec = bytes32(even[3].toUint());
        uint evenDecPl   = even[4].toUint();

        uint oddGTP = odd[0].toUint();
        uint oddScorePL = odd[1].toUint();
        uint oddScoreOP = odd[2].toUint();
        bytes32 oddHashDec = bytes32(odd[3].toUint());
        uint oddDecPL   = odd[4].toUint();
        uint oddDecOP   = odd[5].toUint();
        uint oddSalt    = odd[6].toUint();

        require(evenHashDec == oddHashDec,  "HashDecision should not change");
        require(evenHashDec == keccak256(abi.encodePacked(oddDecOP, oddSalt)), "Opponent decision does not match hash");

        require(evenDecPl == oddDecPL, "PLayer decision should not change");
        require(oddDecOP < 3, "Opponent decision must be 0, 1 or 2");

        if(oddDecPL == oddDecOP) {
            require(evenGTP == oddGTP, "GamesToPlay does not go down on draw");
            require(evenScorePL == oddScorePL, "Player Score does not increase on draw");
            require(evenScoreOP == oddScoreOP, "Opponent Score does not increase on draw");
        } else if(
            (oddDecPL == 0  && oddDecOP == 2) ||
            (oddDecPL == 1  && oddDecOP == 0) ||
            (oddDecPL == 2  && oddDecOP == 1)
        ) {
            require(evenGTP == oddGTP + 1, "GamesToPlay should decrease");
            require(evenScorePL + 1 == oddScorePL , "Player Score increases due to win");
            require(evenScoreOP == oddScoreOP, "Opponent Score must say the same due to loss");
        } else {
            require(evenGTP == oddGTP + 1, "GamesToPlay should decrease");
            require(evenScorePL == oddScorePL, "Player Score must  say the same due to loss");
            require(evenScoreOP + 1 == oddScoreOP, "Opponent Score increases due to win");
        }

        if(!isFinal) {
            require(odd[7].toUint() != 0, "Invalid decisionHash for next turn");
        }
    }

    function validateOddToEven(bytes memory oddTurn, bytes memory evenTurn, bool isFirst) private pure {
        RLPReader.RLPItem[] memory even = evenTurn.toRlpItem().toList();
        RLPReader.RLPItem[] memory odd = oddTurn.toRlpItem().toList();

        require(even.length == 5, "Invalid even turn RLP length");

        uint evenGTP = even[0].toUint();
        uint evenScorePL = even[1].toUint();
        uint evenScoreOP = even[2].toUint();
        bytes32 evenHashDec = bytes32(even[3].toUint());
        uint evenDecPl   = even[4].toUint();

        uint oddGTP = odd[0].toUint();
        uint oddScorePL = odd[1].toUint();
        uint oddScoreOP = odd[2].toUint();
        bytes32 oddNewHashDec;

        if(isFirst) {
            oddNewHashDec = bytes32(odd[3].toUint());
        } else {
            oddNewHashDec = bytes32(odd[7].toUint());
        }

        require(evenGTP == oddGTP, "GamesToPlay must stay de same");
        require(evenScorePL == oddScorePL, "Player score must stay de same");
        require(evenScoreOP == oddScoreOP, "Opponent score must stay de same");
        require(evenHashDec == oddNewHashDec, "Hash decision must stay de same");
        require(evenDecPl < 3, "Player decision must be 0, 1 or 2");
    }

    function winner(bytes memory state, uint turnNum, address player, address opponent) public pure returns (address) {
        if(isOver(state, turnNum)) {
            RLPReader.RLPItem[] memory ending = state.toRlpItem().toList();
            return ending[1].toUint() > ending[2].toUint() ? player : opponent;
        } else {
            return address(0);
        }
    }

    function isOver(bytes memory state, uint /*turnNum*/) public pure returns (bool) {
        RLPReader.RLPItem[] memory ending = state.toRlpItem().toList();
        return ending[0].toUint() == 0;
    }

    function mover(bytes memory /*state*/, uint turnNum, address player, address opponent) public pure returns (address) {
        return turnNum%2 == 0 ? player: opponent;
    }

    event RPSRequested(uint gameId, address indexed player, address indexed opponent, uint gamesToPlay);
    event RPSStarted(uint gameId, address indexed player, address indexed opponent, uint gamesToPlay);

    //TODO add validator
    function eventRequestState(uint gameId, bytes memory state, address player, address opponent) public {
        uint gamesToPlay = state.toRlpItem().toList()[0].toUint();
        emit RPSRequested(gameId, player, opponent, gamesToPlay);
    }
    //TODO add validator
    function eventStartState(uint gameId, bytes memory state, address player, address opponent) public {
        uint gamesToPlay = state.toRlpItem().toList()[0].toUint();
        emit RPSStarted(gameId, player, opponent, gamesToPlay);
    }

}
