pragma solidity ^0.5.12;
pragma experimental ABIEncoderV2;

import "./Pokedex.sol";

library BattleDamageCalculator {

    uint constant ATTACK_POWER = 20;
    uint constant CONFUSED_ATTACK_POWER = 10;
    uint constant STATUS_HIT_CHANCE = 0xBE;
    uint constant LEVEL = 100;

    uint constant FIRE_ATK_REDUC    = 80;
    uint constant NORMAL_ATK_REDUC  = 50;
    uint constant GHOST_ATK_REDUC   = 70;
    uint constant DRAGON_ATK_INC   = 130;

    uint constant WATER_SPEED_REDUC     = 60;
    uint constant ELECTRIC_SPEED_REDUC  = 60;
    uint constant FLYING_SPEED_INC      = 150;

    uint constant ROCK_DEF_INC = 150;

    uint constant WATER_SPATK_REDUC    = 80;
    uint constant DRAGON_SPATK_INC   = 130;

    uint constant STEEL_SPDEF_INC   = 150;

    uint8 constant BUG_MISS_ODDS      = uint8(uint(50) * 100 * 255 / 10000);
    uint8 constant ELECTRIC_MISS_ODDS = uint8(uint(25) * 100 * 255 / 10000);
    uint8 constant FAIRY_SAME_SEX_MISS_ODDS = uint8(uint(35) * 100 * 255 / 10000);
    uint8 constant FAIRY_DIFF_SEX_MISS_ODDS = uint8(uint(70) * 100 * 255 / 10000);
    uint8 constant PSYCHIC_MISS_ODDS = uint8(uint(15) * 100 * 255 / 10000);
    uint8 constant GHOST_MISS_ODDS   = uint8(uint(30) * 100 * 255 / 10000);


    uint8 constant BONUS_EFFECTIVE = 150;
    uint8 constant BONUS_INEFFECTIVE = 75;
    uint8 constant SINGLE_TYPE_BOOST = 120;

    uint constant decimals = 1000000;

    enum Moves {
        RECHARGE,
        CLEANSE,
        PROTECT,
        SHIELD_BREAK,
        ATK1,
        SPATK1,
        STATUS1,
        ATK2,
        SPATK2,
        STATUS2
    }

    struct CryptoMonState {
        uint hp;
        bool status1;
        bool status2;
        uint charges;
        Pokedex.Pokemon cryptoMon;
        Pokedex.PokemonData data;
        Moves move;
    }

    struct BattleState {
        CryptoMonState player;
        CryptoMonState opponent;
        bytes32 random;
    }

    function calculateBattle(BattleState memory state) internal pure returns (BattleState memory) {

        uint playerSpeed   = calculateEffectiveSpeed(state.player, state.opponent);
        uint opponentSpeed = calculateEffectiveSpeed(state.opponent, state.player);

        bool switchTurn = playerSpeed < opponentSpeed;
        if(playerSpeed == opponentSpeed) {
            (bytes32 random, uint8 nextR) = getNextR(state.random);
            state.random = random;
            switchTurn = nextR > uint8(0x0F);
        }

        if(switchTurn) {
            state = swap(state);
        }

        state = moveTurn(state);

        if(someoneDied(state)) return swapIfSwitched(state, switchTurn);

        state = moveTurn(swap(state));

        if(someoneDied(state)) return swapIfSwitched(state, !switchTurn);

        state = calculateEndDamage(swap(state));

        if(someoneDied(state)) return swapIfSwitched(state, switchTurn);

        state = calculateEndDamage(swap(state));

        if(someoneDied(state)) return swapIfSwitched(state, !switchTurn);

        return swapIfSwitched(state, !switchTurn);
    }

    function swap(BattleState memory state) private pure returns (BattleState memory) {
        CryptoMonState memory first = state.opponent;
        state.opponent = state.player;
        state.player = first;
        return state;
    }

    function swapIfSwitched(BattleState memory state, bool switched) private pure returns (BattleState memory) {
        if(switched) {
            return swap(state);
        }

        return state;
    }

    function moveTurn(BattleState memory state) private pure returns (BattleState memory) {
        if(state.player.move == Moves.PROTECT) return state;

        if(needsCharge(state.player.move)) {
            require(state.player.charges > 0);
            state.player.charges = state.player.charges - 1;
        }

        if(state.player.move == Moves.RECHARGE) {
            require(state.player.charges < 3);
            state.player.charges = state.player.charges + 1;
            return state;
        }

        if(usesFirstType(state.player.move)) {
            require(state.player.data.type1 != Pokedex.Type.Unknown);
        }

        if(usesSecondType(state.player.move)) {
            require(state.player.data.type2 != Pokedex.Type.Unknown);
        }

        if(isAttacking(state.player.move)) {
            (bytes32 random1, uint8 criticalR) = getNextR(state.random);
            (bytes32 random2, uint8 jitterR)   = getNextR(random1);
            (bytes32 random3, uint8 hitR)      = getNextR(random2);
            state.random = random3;
            bool hit = willHit(state.player, state.opponent, hitR);
            if(hit) {
                uint damage = calculateEffectiveDamage(state.player, state.opponent, criticalR, jitterR);

                if(state.player.data.type2 == Pokedex.Type.Unknown) {
                    damage = damage * SINGLE_TYPE_BOOST / 100;
                }

                if(state.opponent.hp < damage) {
                    state.opponent.hp = 0;
                } else {
                    state.opponent.hp = state.opponent.hp - damage;
                }
            } else {
                state.player.charges = state.player.charges + 1;
                if(isConfused(state.player, state.opponent)) {
                    uint effectiveAtk = state.player.cryptoMon.stats.atk;
                    uint effectiveDef = state.player.cryptoMon.stats.def;
                    uint confusedDmg = ((2*LEVEL/5 + 2) * CONFUSED_ATTACK_POWER * effectiveAtk / effectiveDef)/50 + 2;
                    if(state.player.hp < confusedDmg) {
                        state.player.hp = 0;
                    } else {
                        state.player.hp = state.player.hp - confusedDmg;
                    }
                }
            }

            return state;
        }

        if(state.player.move == Moves.SHIELD_BREAK) {
            if(state.opponent.move == Moves.PROTECT) {
                uint shieldBreakDmg = state.opponent.cryptoMon.stats.hp / 3;
                if(state.opponent.hp < shieldBreakDmg) {
                    state.opponent.hp = 0;
                } else {
                    state.opponent.hp = state.opponent.hp - shieldBreakDmg;
                }

                return state;
            } else {
                //No returning charge cause shield break should only be used on Protect spam
                return state;
            }
        }

        if(state.player.move == Moves.STATUS1) {
            (bytes32 random, uint8 statusHit) = getNextR(state.random);
            state.random = random;
            if(canStatus(state, statusHit)){
                state.opponent.status1 = true;
            } else {
                state.player.charges = state.player.charges + 1;
            }
            return state;
        }

        if(state.player.move == Moves.STATUS2) {
            (bytes32 random, uint8 statusHit) = getNextR(state.random);
            state.random = random;
            if(canStatus(state, statusHit)){
                state.opponent.status2 = true;
            } else {
                state.player.charges = state.player.charges + 1;
            }
            return state;
        }

        if(state.player.move == Moves.CLEANSE) {
            state.player.status1 = false;
            state.player.status2 = false;
            return state;
        }

        return state;
    }

    function canStatus(BattleState memory state, uint8 random) private pure returns (bool) {
        if(state.player.status1 && state.opponent.data.type1 != Pokedex.Type.Ice) return false;
        if(state.player.status2 && state.opponent.data.type2 != Pokedex.Type.Ice) return false;
        return random < STATUS_HIT_CHANCE;
    }


    function calculateEffectiveDamage(
        CryptoMonState memory state,
        CryptoMonState memory otherState,
        uint8 criticalR, uint8 jitterR) private pure returns (uint) {

        if(otherState.move == Moves.PROTECT) return 0;

        uint damage;

        if(state.move == Moves.ATK1 || state.move == Moves.ATK2) {
            uint effectiveAtk = calculateEffectiveAtk(state, otherState);
            uint effectiveDef = calculateEffectiveDef(otherState, state);

            damage = ((2*LEVEL/5 + 2) * ATTACK_POWER * effectiveAtk / effectiveDef)/50 + 2;
        } else if(state.move == Moves.SPATK1 || state.move == Moves.SPATK2) {
            uint effectiveSpAtk = calculateEffectiveSpAtk(state, otherState);
            uint effectiveSpDef = calculateEffectiveSpDef(otherState, state);

            damage = ((2*LEVEL/5 + 2) * ATTACK_POWER * effectiveSpAtk / effectiveSpDef)/50 + 2;
        } else {
            revert("Attacking move should be an attacking move");
        }

        bool isCritical = criticalR < getCriticalHitThreshold(state, otherState);
        if(isCritical) damage = damage * 150 / 100;

        uint jitter = (jitterR * decimals / 255 * (255-217)) + (217 * decimals);
        damage = damage * jitter / 255 / decimals;

        Pokedex.Type attackingType;
        if(usesFirstType(state.move)) {
            attackingType = state.data.type1;
        } else {
            attackingType = state.data.type2;
        }
        uint multiplierId = getMultiplierID(attackingType, otherState.data.type1, otherState.data.type2);
        if(multiplierId == 3) {
            return damage;
        }

        if(multiplierId > 4) {
            damage = damage * BONUS_EFFECTIVE / 100;
            if(multiplierId == 5) {
                damage = damage * BONUS_EFFECTIVE / 100;
            }
            return damage;
        }

        if(multiplierId < 3) {
            damage = damage * BONUS_INEFFECTIVE / 100;
            if(multiplierId < 2) {
                damage = damage * BONUS_INEFFECTIVE / 100;
                if(multiplierId == 0) {
                    damage = damage * BONUS_INEFFECTIVE / 100;
                }
            }

        }

        return damage;
    }

    //SPEED ----------------------------------------
    function calculateEffectiveSpeed(CryptoMonState memory state, CryptoMonState memory otherState) private pure returns (uint) {
        uint speed = state.cryptoMon.stats.speed;
        if(state.status1) speed = getSpeedModified(speed, otherState.data.type1);
        if(state.status2) speed = getSpeedModified(speed, otherState.data.type2);
        if(otherState.status2) speed = getSpeedModifiedByOpponent(speed, state.data.type2);
        if(otherState.status2) speed = getSpeedModifiedByOpponent(speed, state.data.type2);
        return speed;
    }

    function getSpeedModified(uint baseSpeed, Pokedex.Type status)  private pure returns (uint){
        if(status == Pokedex.Type.Water) return baseSpeed * WATER_SPEED_REDUC /100;
        if(status == Pokedex.Type.Electric) return baseSpeed * ELECTRIC_SPEED_REDUC /100;
        if(status == Pokedex.Type.Ice) return 0;
        return baseSpeed;
    }

    function getSpeedModifiedByOpponent(uint baseSpeed, Pokedex.Type status)  private pure returns (uint){
        if(status == Pokedex.Type.Flying) return baseSpeed * FLYING_SPEED_INC /100;
        return baseSpeed;
    }
    // -----------------------------------------------


    //ATTACK ----------------------------------------
    function calculateEffectiveAtk(CryptoMonState memory state, CryptoMonState memory otherState) private pure returns (uint) {
        uint atk = state.cryptoMon.stats.atk;
        if(state.status1) atk = getAtkModified(atk, otherState.data.type1);
        if(state.status2) atk = getAtkModified(atk, otherState.data.type2);
        if(otherState.status2) atk = getAtkModifiedByOpponent(atk, state.data.type2);
        if(otherState.status2) atk = getAtkModifiedByOpponent(atk, state.data.type2);
        return atk;
    }

    function getAtkModified(uint baseAtk, Pokedex.Type status)  private pure returns (uint){
        if(status == Pokedex.Type.Fire) return baseAtk * FIRE_ATK_REDUC / 100;
        if(status == Pokedex.Type.Normal) return baseAtk * NORMAL_ATK_REDUC / 100;
        if(status == Pokedex.Type.Ghost) return baseAtk * GHOST_ATK_REDUC / 100;
        return baseAtk;
    }

    function getAtkModifiedByOpponent(uint baseAtk, Pokedex.Type status)  private pure returns (uint){
        if(status == Pokedex.Type.Dragon) return baseAtk * DRAGON_ATK_INC /100;
        return baseAtk;
    }
    // -----------------------------------------------

    //DEFENSE ----------------------------------------
    function calculateEffectiveDef(CryptoMonState memory state, CryptoMonState memory otherState) private pure returns (uint) {
        uint def = state.cryptoMon.stats.def;
        if(state.status1) def = getDefModified(def, otherState.data.type1);
        if(state.status2) def = getDefModified(def, otherState.data.type2);
        if(otherState.status2) def = getDefModifiedByOpponent(def, state.data.type2);
        if(otherState.status2) def = getDefModifiedByOpponent(def, state.data.type2);
        return def;
    }

    function getDefModified(uint baseDef, Pokedex.Type /*status*/)  private pure returns (uint){
        return baseDef;
    }

    function getDefModifiedByOpponent(uint baseDef, Pokedex.Type status)  private pure returns (uint){
        if(status == Pokedex.Type.Rock) return baseDef * ROCK_DEF_INC /100;
        return baseDef;
    }
    // -----------------------------------------------


    //SPATTACK ----------------------------------------
    function calculateEffectiveSpAtk(CryptoMonState memory state, CryptoMonState memory otherState) private pure returns (uint) {
        uint spAtk = state.cryptoMon.stats.spAtk;
        if(state.status1) spAtk = getSpAtkModified(spAtk, otherState.data.type1);
        if(state.status2) spAtk = getSpAtkModified(spAtk, otherState.data.type2);
        if(otherState.status2) spAtk = getSpAtkModifiedByOpponent(spAtk, state.data.type2);
        if(otherState.status2) spAtk = getSpAtkModifiedByOpponent(spAtk, state.data.type2);
        return spAtk;
    }

    function getSpAtkModified(uint baseSpAtk, Pokedex.Type status)  private pure returns (uint){
        if(status == Pokedex.Type.Water) return baseSpAtk * WATER_SPATK_REDUC / 100;
        return baseSpAtk;
    }

    function getSpAtkModifiedByOpponent(uint baseSpAtk, Pokedex.Type status)  private pure returns (uint){
        if(status == Pokedex.Type.Dragon) return baseSpAtk * DRAGON_SPATK_INC /100;
        return baseSpAtk;
    }
    // -----------------------------------------------

    //SPDEFENSE ----------------------------------------
    function calculateEffectiveSpDef(CryptoMonState memory state, CryptoMonState memory otherState) private pure returns (uint) {
        uint spDef = state.cryptoMon.stats.spDef;
        if(state.status1) spDef = getSpDefModified(spDef, otherState.data.type1);
        if(state.status2) spDef = getSpDefModified(spDef, otherState.data.type2);
        if(otherState.status2) spDef = getSpDefModifiedByOpponent(spDef, state.data.type2);
        if(otherState.status2) spDef = getSpDefModifiedByOpponent(spDef, state.data.type2);
        return spDef;
    }

    function getSpDefModified(uint baseSpDef, Pokedex.Type /*status*/)  private pure returns (uint){
        return baseSpDef;
    }

    function getSpDefModifiedByOpponent(uint baseSpDef, Pokedex.Type status)  private pure returns (uint){
        if(status == Pokedex.Type.Steel) return baseSpDef * STEEL_SPDEF_INC /100;
        return baseSpDef;
    }
    // -----------------------------------------------

    // CRITICAL ---------------------------------------------
    function getCriticalHitThreshold(
        CryptoMonState memory state,
        CryptoMonState memory otherState
    ) private pure returns (uint8) {

        uint T = state.data.base.speed;
        if( (otherState.status1 && state.data.type1 == Pokedex.Type.Fighting)
            || (otherState.status2 && state.data.type2 == Pokedex.Type.Fighting)
        ) {
            T =T * 8;
        } else {
            T = T / 2;
        }
        if(T > 0xFF) {
            return 0xFF;
        }
        return uint8(T);
    }
    // ------------------------------------------------------------

    //MISS HIT -------------------------------------------
    function willHit(CryptoMonState memory state, CryptoMonState memory otherState, uint8 random) private pure returns (bool) {
        if(state.status1 && state.status2) {
            uint8 odds1 = getMissOdds(otherState.data.type1, state.cryptoMon.gender == otherState.cryptoMon.gender);
            uint8 odds2 = getMissOdds(otherState.data.type2, state.cryptoMon.gender == otherState.cryptoMon.gender);
            uint8 odds = 255 - uint8((uint(255-odds1) * decimals / 255) *  (uint(255-odds2) * decimals / 255) * 255 / (decimals * decimals));
            return random > odds;
        } else if(state.status1) {
            return random > getMissOdds(otherState.data.type1, state.cryptoMon.gender == otherState.cryptoMon.gender);
        } else if(state.status2) {
            return random > getMissOdds(otherState.data.type2, state.cryptoMon.gender == otherState.cryptoMon.gender);
        } else {
            return true;
        }
    }

    function getMissOdds(Pokedex.Type ptype, bool sameSex) private pure returns (uint8) {
        if(ptype == Pokedex.Type.Bug) return BUG_MISS_ODDS;
        if(ptype == Pokedex.Type.Electric) return ELECTRIC_MISS_ODDS;
        if(ptype == Pokedex.Type.Ghost) return GHOST_MISS_ODDS;
        if(ptype == Pokedex.Type.Psychic) return PSYCHIC_MISS_ODDS;
        if(ptype == Pokedex.Type.Fairy) {
            if(sameSex) return FAIRY_SAME_SEX_MISS_ODDS;
            return FAIRY_DIFF_SEX_MISS_ODDS;
        }

        return 0;
    }


    function isConfused(CryptoMonState memory state, CryptoMonState memory otherState) private pure returns (bool) {
        if(state.status1 && otherState.data.type1 == Pokedex.Type.Psychic) return true;
        if(state.status2 && otherState.data.type2 == Pokedex.Type.Psychic) return true;
        return false;
    }
    // --------------------------------------------------


    function calculateEndDamage(BattleState memory state) private pure returns (BattleState memory) {
        uint healing;
        if(state.opponent.status1) healing = healing + calculateEndHealingForType(state, state.player.data.type1);
        if(state.opponent.status2) healing = healing + calculateEndHealingForType(state, state.player.data.type2);

        if(state.player.hp + healing < state.player.cryptoMon.stats.hp) {
            state.player.hp = state.player.hp + healing;
        } else {
            state.player.hp = state.player.cryptoMon.stats.hp;
        }

        uint damage;
        if(state.player.status1) damage = damage + calculateEndDamageForType(state, state.opponent.data.type1);
        if(state.player.status2) damage = damage + calculateEndDamageForType(state, state.opponent.data.type2);

        if(state.player.hp < damage) {
            state.player.hp = 0;
        } else {
            state.player.hp = state.player.hp - damage;
        }

        return state;
    }

    function calculateEndDamageForType(BattleState memory state, Pokedex.Type ptype) private pure returns (uint) {
        if(ptype == Pokedex.Type.Grass) return state.player.cryptoMon.stats.hp * decimals / 16 / decimals;
        if(ptype == Pokedex.Type.Poison) return state.player.cryptoMon.stats.hp * decimals / 10 / decimals;
        if(ptype == Pokedex.Type.Fire) return state.player.cryptoMon.stats.hp * decimals / 16 / decimals;
        if(ptype == Pokedex.Type.Flying) return state.player.cryptoMon.stats.hp * decimals / 16 / decimals;
        if(ptype == Pokedex.Type.Rock) return state.player.cryptoMon.stats.hp * decimals / 16 / decimals;
        if(ptype == Pokedex.Type.Ground && (isAttacking(state.player.move) || isStatus(state.player.move))) {
            return state.player.cryptoMon.stats.hp * decimals / 16 / decimals;
        }

        return 0;
    }

    function calculateEndHealingForType(BattleState memory state, Pokedex.Type ptype) private pure returns (uint) {
        if(ptype == Pokedex.Type.Grass) return state.opponent.cryptoMon.stats.hp * decimals / 16 / decimals;
        return 0;
    }

    //RANDOM ---------------------------------------
    function getNextR(bytes32 random) private pure returns (bytes32, uint8) {
        uint8 nextR =  uint8(uint256(random & bytes32(uint256(0xFF))));
        return (shiftRandom(random), nextR);
    }

    function shiftRandom(bytes32 random) private pure returns (bytes32) {
        return bytes32(uint256(random) / (2**8));
    }
    // -----------------------------------------------------


    function needsCharge(Moves move) internal pure returns (bool) {
        return move != Moves.RECHARGE && move != Moves.PROTECT;
    }

    function isAttacking(Moves move) private pure returns (bool) {
        return move == Moves.ATK1 || move == Moves.ATK2 || move == Moves.SPATK1 || move == Moves.SPATK2;
    }

    function isStatus(Moves move) private pure returns (bool) {
        return move == Moves.STATUS1 || move == Moves.STATUS2;
    }

    function someoneDied(BattleState memory state) private pure returns (bool) {
        return state.player.hp == 0 || state.opponent.hp == 0;
    }

    function usesFirstType(Moves move) public pure returns (bool) {
        return move == Moves.ATK1 || move == Moves.SPATK1 || move == Moves.STATUS1;
    }

    function usesSecondType(Moves move) public pure returns (bool) {
        return move == Moves.ATK2 || move == Moves.SPATK2 || move == Moves.STATUS2;
    }


    function getMultiplierID(
        Pokedex.Type attackingType,
        Pokedex.Type defendingType1,
        Pokedex.Type defendingType2) public pure returns(uint8) {
        //0 - 25 - 50 - 100 - 200 - 400
        //0 - 1  - 2  -  3  - 4   - 5
        uint8 multiplierID = 3;

        if(attackingType == Pokedex.Type.Normal) {
            if(defendingType1 == Pokedex.Type.Ghost || defendingType2 == Pokedex.Type.Ghost) return 0;
            if(defendingType1 == Pokedex.Type.Rock || defendingType2 == Pokedex.Type.Rock) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Steel || defendingType2 == Pokedex.Type.Steel) multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Fighting) {
            if(defendingType1 == Pokedex.Type.Ghost || defendingType2 == Pokedex.Type.Ghost) return 0;
            if(defendingType1 == Pokedex.Type.Rock   || defendingType2 == Pokedex.Type.Rock)   multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Steel  || defendingType2 == Pokedex.Type.Steel)  multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Ice    || defendingType2 == Pokedex.Type.Ice)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Dark   || defendingType2 == Pokedex.Type.Dark)   multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Flying || defendingType2 == Pokedex.Type.Flying) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Poison || defendingType2 == Pokedex.Type.Poison) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Psychic|| defendingType2 == Pokedex.Type.Psychic)multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Bug    || defendingType2 == Pokedex.Type.Bug)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fairy  || defendingType2 == Pokedex.Type.Fairy)  multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Flying) {
            if(defendingType1 == Pokedex.Type.Fighting || defendingType2 == Pokedex.Type.Fighting) multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Bug || defendingType2 == Pokedex.Type.Bug) multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Grass    || defendingType2 == Pokedex.Type.Grass)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Rock || defendingType2 == Pokedex.Type.Rock) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Steel   || defendingType2 == Pokedex.Type.Steel)   multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Electric  || defendingType2 == Pokedex.Type.Electric)  multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Poison) {
            if(defendingType1 == Pokedex.Type.Steel  || defendingType2 == Pokedex.Type.Steel) return 0;
            if(defendingType1 == Pokedex.Type.Grass  || defendingType2 == Pokedex.Type.Grass)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Fairy  || defendingType2 == Pokedex.Type.Fairy)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Poison || defendingType2 == Pokedex.Type.Poison) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Ground || defendingType2 == Pokedex.Type.Ground) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Rock   || defendingType2 == Pokedex.Type.Rock) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Ghost  || defendingType2 == Pokedex.Type.Ghost)   multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Ground) {
            if(defendingType1 == Pokedex.Type.Poison || defendingType2 == Pokedex.Type.Poison) multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Rock || defendingType2 == Pokedex.Type.Rock) multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Steel || defendingType2 == Pokedex.Type.Steel) multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Fire || defendingType2 == Pokedex.Type.Fire) multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Electric || defendingType2 == Pokedex.Type.Electric) multiplierID = multiplierID + 1;

            if(defendingType1 == Pokedex.Type.Flying || defendingType2 == Pokedex.Type.Flying) return 0;
            if(defendingType1 == Pokedex.Type.Bug   || defendingType2 == Pokedex.Type.Bug) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Grass  || defendingType2 == Pokedex.Type.Grass) multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Rock) {
            if(defendingType1 == Pokedex.Type.Flying  || defendingType2 == Pokedex.Type.Flying)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Bug  || defendingType2 == Pokedex.Type.Bug)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Fire  || defendingType2 == Pokedex.Type.Fire)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Ice  || defendingType2 == Pokedex.Type.Ice)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Fighting  || defendingType2 == Pokedex.Type.Fighting)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Ground || defendingType2 == Pokedex.Type.Ground) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Steel || defendingType2 == Pokedex.Type.Steel) multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Bug) {
            if(defendingType1 == Pokedex.Type.Grass  || defendingType2 == Pokedex.Type.Grass)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Psychic  || defendingType2 == Pokedex.Type.Psychic)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Dark  || defendingType2 == Pokedex.Type.Dark)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Fighting  || defendingType2 == Pokedex.Type.Fighting)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Flying  || defendingType2 == Pokedex.Type.Flying)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Poison  || defendingType2 == Pokedex.Type.Poison)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Ghost  || defendingType2 == Pokedex.Type.Ghost)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Steel || defendingType2 == Pokedex.Type.Steel) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fire || defendingType2 == Pokedex.Type.Fire) multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fairy || defendingType2 == Pokedex.Type.Fairy) multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Ghost) {
            if(defendingType1 == Pokedex.Type.Ghost  || defendingType2 == Pokedex.Type.Ghost)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Psychic  || defendingType2 == Pokedex.Type.Psychic)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Normal  || defendingType2 == Pokedex.Type.Normal)    return 0;
            if(defendingType1 == Pokedex.Type.Dark  || defendingType2 == Pokedex.Type.Dark)    multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Steel) {
            if(defendingType1 == Pokedex.Type.Rock  || defendingType2 == Pokedex.Type.Rock)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Ice  || defendingType2 == Pokedex.Type.Ice)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Fairy  || defendingType2 == Pokedex.Type.Fairy)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Steel  || defendingType2 == Pokedex.Type.Steel)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fire  || defendingType2 == Pokedex.Type.Fire)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Water  || defendingType2 == Pokedex.Type.Water)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Electric  || defendingType2 == Pokedex.Type.Electric)    multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Fire) {
            if(defendingType1 == Pokedex.Type.Bug  || defendingType2 == Pokedex.Type.Bug)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Steel  || defendingType2 == Pokedex.Type.Steel)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Grass  || defendingType2 == Pokedex.Type.Grass)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Ice  || defendingType2 == Pokedex.Type.Ice)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Rock  || defendingType2 == Pokedex.Type.Rock)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fire  || defendingType2 == Pokedex.Type.Fire)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Water  || defendingType2 == Pokedex.Type.Water)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Dragon  || defendingType2 == Pokedex.Type.Dragon)    multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Water) {
            if(defendingType1 == Pokedex.Type.Ground  || defendingType2 == Pokedex.Type.Ground)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Rock  || defendingType2 == Pokedex.Type.Rock)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Fire  || defendingType2 == Pokedex.Type.Fire)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Water  || defendingType2 == Pokedex.Type.Water)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Grass  || defendingType2 == Pokedex.Type.Grass)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Dragon  || defendingType2 == Pokedex.Type.Dragon)    multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Grass) {
            if(defendingType1 == Pokedex.Type.Ground  || defendingType2 == Pokedex.Type.Ground)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Rock  || defendingType2 == Pokedex.Type.Rock)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Water  || defendingType2 == Pokedex.Type.Water)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Flying  || defendingType2 == Pokedex.Type.Flying)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Poison  || defendingType2 == Pokedex.Type.Poison)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Bug  || defendingType2 == Pokedex.Type.Bug)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Steel  || defendingType2 == Pokedex.Type.Steel)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fire  || defendingType2 == Pokedex.Type.Fire)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Grass  || defendingType2 == Pokedex.Type.Grass)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Dragon  || defendingType2 == Pokedex.Type.Dragon)    multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Electric) {
            if(defendingType1 == Pokedex.Type.Water  || defendingType2 == Pokedex.Type.Water)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Flying  || defendingType2 == Pokedex.Type.Flying)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Ground  || defendingType2 == Pokedex.Type.Ground)   return 0;
            if(defendingType1 == Pokedex.Type.Grass  || defendingType2 == Pokedex.Type.Grass)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Electric  || defendingType2 == Pokedex.Type.Electric)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Dragon  || defendingType2 == Pokedex.Type.Dragon)    multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Psychic) {
            if(defendingType1 == Pokedex.Type.Fighting  || defendingType2 == Pokedex.Type.Fighting)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Poison  || defendingType2 == Pokedex.Type.Poison)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Steel  || defendingType2 == Pokedex.Type.Steel)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Psychic  || defendingType2 == Pokedex.Type.Psychic)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Dark  || defendingType2 == Pokedex.Type.Dark)    return 0;
        } else if(attackingType == Pokedex.Type.Ice) {
            if(defendingType1 == Pokedex.Type.Flying  || defendingType2 == Pokedex.Type.Flying)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Ground  || defendingType2 == Pokedex.Type.Ground)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Grass  || defendingType2 == Pokedex.Type.Grass)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Dragon  || defendingType2 == Pokedex.Type.Dragon)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Steel  || defendingType2 == Pokedex.Type.Steel)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fire  || defendingType2 == Pokedex.Type.Fire)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Water  || defendingType2 == Pokedex.Type.Water)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Ice  || defendingType2 == Pokedex.Type.Ice)    multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Dragon) {
            if(defendingType1 == Pokedex.Type.Dragon  || defendingType2 == Pokedex.Type.Dragon)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Steel  || defendingType2 == Pokedex.Type.Steel)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fairy  || defendingType2 == Pokedex.Type.Fairy)    return 0;
        } else if(attackingType == Pokedex.Type.Dark) {
            if(defendingType1 == Pokedex.Type.Ghost  || defendingType2 == Pokedex.Type.Ghost)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Psychic  || defendingType2 == Pokedex.Type.Psychic)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Fighting  || defendingType2 == Pokedex.Type.Fighting)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Dark  || defendingType2 == Pokedex.Type.Dark)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fairy  || defendingType2 == Pokedex.Type.Fairy)    multiplierID = multiplierID - 1;
        } else if(attackingType == Pokedex.Type.Fairy) {
            if(defendingType1 == Pokedex.Type.Fighting  || defendingType2 == Pokedex.Type.Fighting)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Dragon  || defendingType2 == Pokedex.Type.Dragon)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Dark  || defendingType2 == Pokedex.Type.Dark)    multiplierID = multiplierID + 1;
            if(defendingType1 == Pokedex.Type.Poison  || defendingType2 == Pokedex.Type.Poison)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Steel  || defendingType2 == Pokedex.Type.Steel)    multiplierID = multiplierID - 1;
            if(defendingType1 == Pokedex.Type.Fire  || defendingType2 == Pokedex.Type.Fire)    multiplierID = multiplierID - 1;
        } else {
            revert("Unknown type");
        }

        return multiplierID;
    }
}