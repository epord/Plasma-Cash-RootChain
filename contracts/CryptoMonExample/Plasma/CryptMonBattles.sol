pragma solidity ^0.5.12;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "../../PlasmaCore/RootChain.sol";
import "../../PlasmaCore/PlasmaTurnGame.sol";

import "../Libraries/CMBTransition.sol";
import "./CryptoMons.sol";

contract CryptoMonBattles is PlasmaTurnGame, Ownable {

    //Signed Player -> Signed OP    -> Signed Pl    -> Signed OP            -> Signed OP
    //initialState  + //State 1    + //State even   + //State odd           +  //State ending (odd)
    //-----------------------------------------------------------------------------------
    //CryptoMonPL   | CryptoMonPL   | CryptoMonPL   | 0 CryptoMonPL        | CryptoMonPL
    //HPPL          | HPPL          | HPPL          | 1 HPPL               | HPPL
    //Status1PL     | Status1PL     | Status1PL     | 2 Status1PL          | Status1PL
    //Status2PL     | Status2PL     | Status2PL     | 3 Status2PL          | Status2PL
    //ChargePL      | ChargePL      | ChargePL      | 4 ChargePL           | ChargePL
    //CryptoMonOP   | CryptoMonOP   | CryptoMonOP   | 5 CryptoMonOP        | CryptoMonOP
    //HPOP          | HPOP          | HPOP          | 6 HPOP               | HPOP
    //Status1OP     | Status1OP     | Status1OP     | 7 Status1OP          | Status1OP
    //Status2OP     | Status2OP     | Status2OP     | 8 Status2OP          | Status2OP
    //ChargeOP      | ChargeOP      | ChargeOP      | 9  ChargeOP          | ChargeOP
    //              | HashDecision  | HashDecision  | 10 HashDecision      | HashDecision
    //              |               | DecisionPL    | 11 DecisionPL        | DecisionPL
    //              |               | SaltPL        | 12 SaltPL            | SaltPL
    //              |               |               | 13 DecisionOp        | DecisionOp
    //              |               |               | 14 SaltOP            | SaltOP
    //              |               |               | 15 nextHashDecision  |

    RootChain rootChain;
    CryptoMons cryptomons;

    constructor(RootChain _rootChain, CryptoMons _cryptomons) public {
        rootChain = _rootChain;
        cryptomons = _cryptomons;
    }

    function validateStartState(
        bytes calldata state,
        address[2] calldata players,
        uint exitDataIndex,
        bytes calldata exitData
    ) external view returns (RootChain.Exit[] memory) {
        return CMBTransition.validateStartState(rootChain, cryptomons, state, players, exitDataIndex, exitData);

    }

    function validateTurnTransition(bytes memory oldState, uint turnNum, bytes memory newState) public view {
        CMBTransition.validateTurnTransition(rootChain, cryptomons, oldState, turnNum, newState);
    }

    function winner(bytes memory state, uint /*turnNum*/, address player, address opponent) public pure returns (address) {
        return CMBTransition.winner(state, player, opponent);
    }

    function isOver(bytes memory state, uint /*turnNum*/) public pure returns (bool) {
        return CMBTransition.isOver(state);
    }

    function mover(bytes memory /*state*/, uint turnNum, address player, address opponent) public pure returns (address) {
        return turnNum%2 == 0 ? player: opponent;
    }

    event CryptoMonBattleRequested(uint indexed gameId, address indexed player, uint indexed CryptoMon);
    event CryptoMonBattleStarted(uint indexed gameId, address indexed player, uint indexed CryptoMon);

    function eventRequestState(uint gameId, bytes memory state, address player, address opponent) public isApproved(msg.sender) {
        (uint CryptoMonPL, uint CryptoMonOP) = CMBTransition.getPlasmaIds(state);
        emit CryptoMonBattleRequested(gameId, player, CryptoMonPL);
        emit CryptoMonBattleRequested(gameId, opponent, CryptoMonOP);
    }

    function eventStartState(uint gameId, bytes memory state, address player, address opponent) public isApproved(msg.sender) {
        (uint CryptoMonPL, uint CryptoMonOP) = CMBTransition.getPlasmaIds(state);
        emit CryptoMonBattleStarted(gameId, player, CryptoMonPL);
        emit CryptoMonBattleStarted(gameId, opponent, CryptoMonOP);
    }

    //VALIDATOR
    mapping (address => bool) public validators;

    function setValidator(address _address, bool value) public onlyOwner {
        validators[_address] = value;
    }

    modifier isApproved(address _address) {
        require(validators[_address]);
        _;
    }


}
