pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "../../PlasmaCore/RootChain.sol";
import "../../PlasmaCore/PlasmaTurnGame.sol";

import "../Libraries/BattleDamageCalculator.sol";
import "../Libraries/Pokedex.sol";
import "./CryptoMons.sol";

contract CryptoMonBattles is PlasmaTurnGame, Ownable {

    using BattleDamageCalculator for BattleDamageCalculator.BattleState;
    using RLPReader for bytes;
    using Transaction for bytes;
    using RLPReader for RLPReader.RLPItem;
    //Signed Player -> Signed OP        -> Signed Player

    //initialState  + //State 1    + //State even   + //State odd  +  //State ending (odd)

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

    enum Battle {
        CryptoMonPL,
        HPPL,
        Status1PL,
        Status2PL,
        ChargePL,
        CryptoMonOP,
        HPOP,
        Status1OP,
        Status2OP,
        ChargeOP,
        HashDecision,
        DecisionPL,
        SaltPL,
        DecisionOP,
        SaltOP,
        NextHashDecision
    }

    enum RLPExitData {
        Slot,
        PrevBlockNumber,
        BlockNumber,
        PrevTxBytes,
        ExitingTxBytes,
        PrevTxInclusionProof,
        ExitingTxInclusionProof,
        Signature
    }

    RootChain rootChain;
    CryptoMons cryptomons;

    uint constant INITIAL_CHARGES = 1;

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

        RLPReader.RLPItem[] memory start = state.toRlpItem().toList();
        require(start.length == uint(Battle.ChargeOP) + 1, "Invalid RLP start length");

        //Player
        Pokedex.Pokemon memory cryptoMonPL = getCryptoMon(start[uint(Battle.CryptoMonPL)].toUint());
        require(cryptoMonPL.id > 0                                        , "Invalid Player Cryptomon");
        require(start[uint(Battle.HPPL)].toUint() == cryptoMonPL.stats.hp , "Player HP does not match");
        require(start[uint(Battle.Status1PL)].toBoolean() == false        , "Player Status1 should be false");
        require(start[uint(Battle.Status2PL)].toBoolean() == false        , "Player Status2 should be false");
        require(start[uint(Battle.ChargePL)].toUint() == INITIAL_CHARGES  , "Player charges must be initial");

        //Opponent
        Pokedex.Pokemon memory cryptoMonOP = getCryptoMon(start[uint(Battle.CryptoMonOP)].toUint());
        require(cryptoMonOP.id > 0                                        , "Invalid Player Cryptomon");
        require(start[uint(Battle.HPOP)].toUint() == cryptoMonOP.stats.hp , "Opponent HP does not match");
        require(start[uint(Battle.Status1OP)].toBoolean() == false        , "Opponent Status1 should be false");
        require(start[uint(Battle.Status2OP)].toBoolean() == false        , "Opponent Status2 should be false");
        require(start[uint(Battle.ChargeOP)].toUint() == INITIAL_CHARGES  , "Opponent charges must be initial");

        RLPReader.RLPItem[] memory rlpExit = exitData.toRlpItem().toList();

        address supposedOwner;
        uint64 token;
        if(exitDataIndex == 0) {
            supposedOwner = players[0];
            token = uint64(start[uint(Battle.CryptoMonPL)].toUint());
        } else {
            supposedOwner = players[1];
            token = uint64(start[uint(Battle.CryptoMonOP)].toUint());
        }

        RootChain.Exit memory exit;
        if (rlpExit.length == 1) {
            (,uint256 depositBlock, address owner, , ) = rootChain.getPlasmaCoin(token);
            require(owner == supposedOwner, "Sender does not match deposit owner");
            exit = RootChain.Exit({
                slot: token,
                prevOwner: address(0),
                owner: owner,
                createdAt: block.timestamp,
                prevBlock: 0,
                exitBlock: depositBlock
            });
        } else {
            uint[2] memory blocks;
            blocks[0] = rlpExit[uint(RLPExitData.PrevBlockNumber)].toUint();
            blocks[1] = rlpExit[uint(RLPExitData.BlockNumber)].toUint();

            require(rlpExit.length == uint(RLPExitData.Signature) + 1, "Invalid exitData RLP Length");
            require(supposedOwner == rlpExit[uint(RLPExitData.ExitingTxBytes)].toBytes().getOwner(),
                "Player does not match exitingTxBytes owner");

            rootChain.checkBothIncludedAndSigned(
                rlpExit[uint(RLPExitData.PrevTxBytes)].toBytes(),
                rlpExit[uint(RLPExitData.ExitingTxBytes)].toBytes(),
                rlpExit[uint(RLPExitData.PrevTxInclusionProof)].toBytes(),
                rlpExit[uint(RLPExitData.ExitingTxInclusionProof)].toBytes(),
                rlpExit[uint(RLPExitData.Signature)].toBytes(),
                blocks
            );

            exit = RootChain.Exit({
                slot: token,
                prevOwner: rlpExit[uint(RLPExitData.PrevTxBytes)].toBytes().getOwner(),
                owner: supposedOwner,
                createdAt: block.timestamp,
                prevBlock: blocks[0],
                exitBlock: blocks[1]
            });
        }

        RootChain.Exit[] memory result = new RootChain.Exit[](1);
        result[0] = exit;
        return result;
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

    function validateTransitionKeepBasics(RLPReader.RLPItem[] memory first, RLPReader.RLPItem[] memory second) private pure {
        //Player
        require(first[uint(Battle.CryptoMonPL)].toUint() == second[uint(Battle.CryptoMonPL)].toUint() ,"Player Cryptomon must stay same");
        require(first[uint(Battle.HPPL)].toUint()        == second[uint(Battle.HPPL)].toUint()        ,"Player HP must stay same");
        require(first[uint(Battle.Status1PL)].toBoolean()== second[uint(Battle.Status1PL)].toBoolean(),"Player Status1 must stay same");
        require(first[uint(Battle.Status2PL)].toBoolean()== second[uint(Battle.Status2PL)].toBoolean(),"Player Status2 must stay same");
        require(first[uint(Battle.ChargePL)].toUint()    == second[uint(Battle.ChargePL)].toUint()    ,"Player charges must stay same");
        //Opponent
        require(first[uint(Battle.CryptoMonOP)].toUint() == second[uint(Battle.CryptoMonOP)].toUint() ,"Opponent Cryptomon must stay same");
        require(first[uint(Battle.HPOP)].toUint()        == second[uint(Battle.HPOP)].toUint()        ,"Opponent HP must stay same");
        require(first[uint(Battle.Status1OP)].toBoolean()== second[uint(Battle.Status1OP)].toBoolean(),"Opponent Status1 must stay same");
        require(first[uint(Battle.Status2OP)].toBoolean()== second[uint(Battle.Status2OP)].toBoolean(),"Opponent Status2 must stay same");
        require(first[uint(Battle.ChargeOP)].toUint()    == second[uint(Battle.ChargeOP)].toUint()    ,"Opponent charges must stay same");
    }

    function validateInitialTransition(bytes memory startState, bytes memory firstTurn) public pure {
        RLPReader.RLPItem[] memory start = startState.toRlpItem().toList();
        RLPReader.RLPItem[] memory first = firstTurn.toRlpItem().toList();

        require(start.length == uint(Battle.ChargeOP) + 1    , "Invalid start turn RLP length");
        require(first.length == uint(Battle.HashDecision) + 1, "Invalid first turn RLP length");
        validateTransitionKeepBasics(start, first);
        require(first[uint(Battle.HashDecision)].toUint() != 0, "Opponent must provide a hash for decision");
    }

    function validateEvenToOdd(bytes memory evenTurn, bytes memory oddTurn, bool isFinal) private view {
        RLPReader.RLPItem[] memory even = evenTurn.toRlpItem().toList();
        RLPReader.RLPItem[] memory odd  = oddTurn.toRlpItem().toList();

        if(isFinal) {
            require(odd.length == uint(Battle.SaltOP) + 1, "Invalid ending turn RLP length");
        } else {
            require(odd.length == uint(Battle.NextHashDecision) + 1, "Invalid ending turn RLP length");
            require(odd[uint(Battle.NextHashDecision)].toUint() != 0, "Opponent must provide a hash for decision");
        }

        require(even[uint(Battle.CryptoMonPL)].toUint() == odd[uint(Battle.CryptoMonPL)].toUint()  , "Player Cryptomon must stay same");
        require(even[uint(Battle.CryptoMonOP)].toUint() == odd[uint(Battle.CryptoMonOP)].toUint()  , "Opponent Cryptomon must stay same");
        require(even[uint(Battle.HashDecision)].toUint()== odd[uint(Battle.HashDecision)].toUint() , "HashDecision must stay same");
        require(even[uint(Battle.DecisionPL  )].toUint()== odd[uint(Battle.DecisionPL   )].toUint(), "Player Decision must stay same");
        require(even[uint(Battle.SaltPL      )].toUint()== odd[uint(Battle.SaltPL      )].toUint() , "Player Salt must stay same");

        require(odd[uint(Battle.DecisionPL)].toUint() <= uint(BattleDamageCalculator.Moves.STATUS2), "Players decision invalid");
        require(odd[uint(Battle.DecisionOP)].toUint() <= uint(BattleDamageCalculator.Moves.STATUS2), "Opponent decision invalid");

        require(bytes32(even[uint(Battle.HashDecision)].toUint()) ==
            keccak256(abi.encodePacked(odd[uint(Battle.DecisionOP)].toUint(), odd[uint(Battle.SaltOP)].toUint())),
                        "Opponent decision does not match hash");

        Pokedex.Pokemon memory cryptoMonPL = getCryptoMon(even[uint(Battle.CryptoMonPL)].toUint());
        Pokedex.PokemonData memory cryptoMonPLData = cryptomons.getPokemonData(cryptoMonPL.id);

        Pokedex.Pokemon memory cryptoMonOP = getCryptoMon(even[uint(Battle.CryptoMonOP)].toUint());
        Pokedex.PokemonData memory cryptoMonOPData = cryptomons.getPokemonData(cryptoMonOP.id);

        BattleDamageCalculator.BattleState memory state = BattleDamageCalculator.BattleState(
            BattleDamageCalculator.CryptoMonState(
                even[uint(Battle.HPPL)].toUint(),
                even[uint(Battle.Status1PL)].toBoolean(),
                even[uint(Battle.Status2PL)].toBoolean(),
                even[uint(Battle.ChargePL)].toUint(),
                cryptoMonPL,
                cryptoMonPLData,
                BattleDamageCalculator.Moves(odd[uint(Battle.DecisionPL)].toUint())
            ),
            BattleDamageCalculator.CryptoMonState(
                even[uint(Battle.HPOP)].toUint(),
                even[uint(Battle.Status1OP)].toBoolean(),
                even[uint(Battle.Status2OP)].toBoolean(),
                even[uint(Battle.ChargeOP)].toUint(),
                cryptoMonOP,
                cryptoMonOPData,
                BattleDamageCalculator.Moves(odd[uint(Battle.DecisionOP)].toUint())
            ),
            keccak256(abi.encodePacked(odd[uint(Battle.SaltPL)].toUint(), odd[uint(Battle.SaltOP)].toUint()))
        );

        state = state.calculateBattle();

        require(state.player.hp      == odd[uint(Battle.HPPL )].toUint()        , "Player HP after battle is incorrect");
        require(state.player.charges == odd[uint(Battle.ChargePL )].toUint()    , "Player charges after battle is incorrect");
        require(state.player.status1 == odd[uint(Battle.Status1PL )].toBoolean(), "Player status1 after battle is incorrect");
        require(state.player.status2 == odd[uint(Battle.Status2PL )].toBoolean(), "Player status2 after battle is incorrect");

        require(state.opponent.hp      == odd[uint(Battle.HPOP )].toUint()        , "Player HP after battle is incorrect");
        require(state.opponent.charges == odd[uint(Battle.ChargeOP )].toUint()    , "Player charges after battle is incorrect");
        require(state.opponent.status1 == odd[uint(Battle.Status1OP )].toBoolean(), "Player status1 after battle is incorrect");
        require(state.opponent.status2 == odd[uint(Battle.Status2OP )].toBoolean(), "Player status2 after battle is incorrect");
    }

    function validateOddToEven(bytes memory oddTurn, bytes memory evenTurn, bool isFirst) private view {
        RLPReader.RLPItem[] memory odd = oddTurn.toRlpItem().toList();
        RLPReader.RLPItem[] memory even = evenTurn.toRlpItem().toList();

        bytes32 oddNewHashDec;
        if(isFirst) {
            require(odd.length == uint(Battle.HashDecision) + 1, "Invalid odd turn RLP length");
            oddNewHashDec = bytes32(odd[uint(Battle.HashDecision)].toUint());
        } else {
            require(odd.length == uint(Battle.NextHashDecision) + 1, "Invalid odd turn RLP length");
            oddNewHashDec = bytes32(odd[uint(Battle.NextHashDecision)].toUint());
        }

        require(even.length == uint(Battle.SaltPL) + 1, "Invalid even turn RLP length");

        validateTransitionKeepBasics(odd, even);

        require(oddNewHashDec == bytes32(even[uint(Battle.HashDecision)].toUint()) , "Hash decision must stay de same");

        uint playerDecision = even[uint(Battle.DecisionPL)].toUint();
        require(playerDecision <= uint(BattleDamageCalculator.Moves.STATUS2), "Players decision invalid");

        if(BattleDamageCalculator.needsCharge(BattleDamageCalculator.Moves(playerDecision))) {
            require(even[uint(Battle.ChargePL)].toUint() > 0, "Player must have charge to make that move");
        }

        Pokedex.Pokemon memory cryptoMonPL = getCryptoMon(even[uint(Battle.CryptoMonPL)].toUint());
        Pokedex.PokemonData memory cryptoMonPLData = cryptomons.getPokemonData(cryptoMonPL.id);

        if(BattleDamageCalculator.usesFirstType(BattleDamageCalculator.Moves(playerDecision))) {
            require(cryptoMonPLData.type1 != Pokedex.Type.Unknown, "Player attack cant be done with Unknown type");
        }

        if(BattleDamageCalculator.usesSecondType(BattleDamageCalculator.Moves(playerDecision))) {
            require(cryptoMonPLData.type2 != Pokedex.Type.Unknown, "Player attack cant be done with Unknown type");
        }

        require(even[uint(Battle.SaltPL)].toUint() != 0, "Player must provide a salt");
    }

    function winner(bytes memory state, uint turnNum, address player, address opponent) public pure returns (address) {
        if(isOver(state, turnNum)) {
            RLPReader.RLPItem[] memory ending = state.toRlpItem().toList();
            uint HPPL = ending[uint(Battle.HPPL)].toUint();
            uint HPOP = ending[uint(Battle.HPOP)].toUint();

            if(HPPL > HPOP) {
                return player;
            } else if(HPOP > HPPL) {
                return opponent;
            } else {
                revert("Both players at 0, there is no simultaneous damage");
            }
        } else {
            return address(0);
        }
    }

    function isOver(bytes memory state, uint /*turnNum*/) public pure returns (bool) {
        RLPReader.RLPItem[] memory ending = state.toRlpItem().toList();
        uint HPPL = ending[uint(Battle.HPPL)].toUint();
        uint HPOP = ending[uint(Battle.HPOP)].toUint();
        return HPPL == 0 || HPOP == 0;
    }

    function mover(bytes memory /*state*/, uint turnNum, address player, address opponent) public pure returns (address) {
        return turnNum%2 == 0 ? player: opponent;
    }

    function getCryptoMon(uint plasmaID) public view returns (Pokedex.Pokemon memory) {
        if(plasmaID >= 2**64) revert("Invalid PlasmaID, it should be a uint64");
        (uint256 cryptoMonId, , , , ) = rootChain.getPlasmaCoin(uint64(plasmaID));
        return cryptomons.getCryptomon(cryptoMonId);
    }

    event CryptoMonBattleRequested(uint indexed gameId, address indexed player, uint indexed CryptoMon);
    event CryptoMonBattleStarted(uint indexed gameId, address indexed player, uint indexed CryptoMon);

    function eventRequestState(uint gameId, bytes memory state, address player, address opponent) public isApproved(msg.sender) {
        RLPReader.RLPItem[] memory decoded = state.toRlpItem().toList();
        uint CryptoMonPL = decoded[uint(Battle.CryptoMonPL)].toUint();
        uint CryptoMonOP = decoded[uint(Battle.CryptoMonOP)].toUint();

        emit CryptoMonBattleRequested(gameId, player, CryptoMonPL);
        emit CryptoMonBattleRequested(gameId, opponent, CryptoMonOP);
    }
    function eventStartState(uint gameId, bytes memory state, address player, address opponent) public isApproved(msg.sender) {
        RLPReader.RLPItem[] memory decoded = state.toRlpItem().toList();
        uint CryptoMonPL = decoded[uint(Battle.CryptoMonPL)].toUint();
        uint CryptoMonOP = decoded[uint(Battle.CryptoMonOP)].toUint();

        emit CryptoMonBattleStarted(gameId, player, CryptoMonPL);
        emit CryptoMonBattleStarted(gameId, opponent, CryptoMonOP);
    }

    //VALIDATOR
    mapping (address => bool) public validators;

    function setValidator(address _address, bool value) public onlyOwner {
        validators[_address] = value;
    }

    modifier isApproved(address _address) {
        require(validators[_address], "Events can only be triggered by validators");
        _;
    }


}
