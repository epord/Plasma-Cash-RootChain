pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

contract Pokedex {

    PokemonData[] pokedex;

    //TODO add nature
    enum Type {
        Normal,
        Fighting,
        Flying,
        Poison,
        Ground,
        Rock,
        Bug,
        Ghost,
        Steel,
        Fire,
        Water,
        Grass,
        Electric,
        Psychic,
        Ice,
        Dragon,
        Dark,
        Fairy,
        Unknown
    }

    enum Gender {
        Male,
        Female,
        Unknown
    }

    struct Stats {
        uint8 hp;
        uint8 atk;
        uint8 def;
        uint8 spAtk;
        uint8 spDef;
        uint8 speed;
    }

    struct PokemonData {
        uint8 id;
        Type type1;
        Type type2;
        Stats base;
    }

    struct Pokemon {
        uint8 id;
        Gender gender;
        bool isShiny;
        Stats IVs;
        Stats stats;
    }


    constructor() public {
        pokedex.push(PokemonData(0, Type.Unknown, Type.Unknown, Stats(0,0,0,0,0,0)));
        pokedex.push(PokemonData(1, Type.Grass, Type.Poison, Stats(45,49,49,65,65,45)));
        pokedex.push(PokemonData(2, Type.Grass, Type.Poison, Stats(60,62,63,80,80,60)));
        pokedex.push(PokemonData(3, Type.Grass, Type.Poison, Stats(80,82,83,100,100,80)));
        pokedex.push(PokemonData(4, Type.Fire, Type.Unknown, Stats(39,52,43,60,50,65)));
        pokedex.push(PokemonData(5, Type.Fire, Type.Unknown, Stats(58,64,58,80,65,80)));
        pokedex.push(PokemonData(6, Type.Fire, Type.Flying, Stats(78,84,78,109,85,100)));
        pokedex.push(PokemonData(7, Type.Water, Type.Unknown, Stats(44,48,65,50,64,43)));
        pokedex.push(PokemonData(8, Type.Water, Type.Unknown, Stats(59,63,80,65,80,58)));
        pokedex.push(PokemonData(9, Type.Water, Type.Unknown, Stats(79,83,100,85,105,78)));
        pokedex.push(PokemonData(10, Type.Bug, Type.Unknown, Stats(45,30,35,20,20,45)));
        pokedex.push(PokemonData(11, Type.Bug, Type.Unknown, Stats(50,20,55,25,25,30)));
        pokedex.push(PokemonData(12, Type.Bug, Type.Flying, Stats(60,45,50,90,80,70)));
        pokedex.push(PokemonData(13, Type.Bug, Type.Poison, Stats(40,35,30,20,20,50)));
        pokedex.push(PokemonData(14, Type.Bug, Type.Poison, Stats(45,25,50,25,25,35)));
        pokedex.push(PokemonData(15, Type.Bug, Type.Poison, Stats(65,90,40,45,80,75)));
        pokedex.push(PokemonData(16, Type.Normal, Type.Flying, Stats(40,45,40,35,35,56)));
        pokedex.push(PokemonData(17, Type.Normal, Type.Flying, Stats(63,60,55,50,50,71)));
        pokedex.push(PokemonData(18, Type.Normal, Type.Flying, Stats(83,80,75,70,70,101)));
        pokedex.push(PokemonData(19, Type.Normal, Type.Unknown, Stats(30,56,35,25,35,72)));
        pokedex.push(PokemonData(20, Type.Normal, Type.Unknown, Stats(55,81,60,50,70,97)));
        pokedex.push(PokemonData(21, Type.Normal, Type.Flying, Stats(40,60,30,31,31,70)));
        pokedex.push(PokemonData(22, Type.Normal, Type.Flying, Stats(65,90,65,61,61,100)));
        pokedex.push(PokemonData(23, Type.Poison, Type.Unknown, Stats(35,60,44,40,54,55)));
        pokedex.push(PokemonData(24, Type.Poison, Type.Unknown, Stats(60,95,69,65,79,80)));
        pokedex.push(PokemonData(25, Type.Electric, Type.Unknown, Stats(35,55,40,50,50,90)));
        pokedex.push(PokemonData(26, Type.Electric, Type.Unknown, Stats(60,90,55,90,80,110)));
        pokedex.push(PokemonData(27, Type.Ground, Type.Unknown, Stats(50,75,85,20,30,40)));
        pokedex.push(PokemonData(28, Type.Ground, Type.Unknown, Stats(75,100,110,45,55,65)));
        pokedex.push(PokemonData(29, Type.Poison, Type.Unknown, Stats(55,47,52,40,40,41)));
        pokedex.push(PokemonData(30, Type.Poison, Type.Unknown, Stats(70,62,67,55,55,56)));
        pokedex.push(PokemonData(31, Type.Poison, Type.Ground, Stats(90,92,87,75,85,76)));
        pokedex.push(PokemonData(32, Type.Poison, Type.Unknown, Stats(46,57,40,40,40,50)));
        pokedex.push(PokemonData(33, Type.Poison, Type.Unknown, Stats(61,72,57,55,55,65)));
        pokedex.push(PokemonData(34, Type.Poison, Type.Ground, Stats(81,102,77,85,75,85)));
        pokedex.push(PokemonData(35, Type.Fairy, Type.Unknown, Stats(70,45,48,60,65,35)));
        pokedex.push(PokemonData(36, Type.Fairy, Type.Unknown, Stats(95,70,73,95,90,60)));
        pokedex.push(PokemonData(37, Type.Fire, Type.Unknown, Stats(38,41,40,50,65,65)));
        pokedex.push(PokemonData(38, Type.Fire, Type.Unknown, Stats(73,76,75,81,100,100)));
        pokedex.push(PokemonData(39, Type.Normal, Type.Fairy, Stats(115,45,20,45,25,20)));
        pokedex.push(PokemonData(40, Type.Normal, Type.Fairy, Stats(140,70,45,85,50,45)));
        pokedex.push(PokemonData(41, Type.Poison, Type.Flying, Stats(40,45,35,30,40,55)));
        pokedex.push(PokemonData(42, Type.Poison, Type.Flying, Stats(75,80,70,65,75,90)));
        pokedex.push(PokemonData(43, Type.Grass, Type.Poison, Stats(45,50,55,75,65,30)));
        pokedex.push(PokemonData(44, Type.Grass, Type.Poison, Stats(60,65,70,85,75,40)));
        pokedex.push(PokemonData(45, Type.Grass, Type.Poison, Stats(75,80,85,110,90,50)));
        pokedex.push(PokemonData(46, Type.Bug, Type.Grass, Stats(35,70,55,45,55,25)));
        pokedex.push(PokemonData(47, Type.Bug, Type.Grass, Stats(60,95,80,60,80,30)));
        pokedex.push(PokemonData(48, Type.Bug, Type.Poison, Stats(60,55,50,40,55,45)));
        pokedex.push(PokemonData(49, Type.Bug, Type.Poison, Stats(70,65,60,90,75,90)));
        pokedex.push(PokemonData(50, Type.Ground, Type.Unknown, Stats(10,55,25,35,45,95)));
        pokedex.push(PokemonData(51, Type.Ground, Type.Unknown, Stats(35,100,50,50,70,120)));
        pokedex.push(PokemonData(52, Type.Normal, Type.Unknown, Stats(40,45,35,40,40,90)));
        pokedex.push(PokemonData(53, Type.Normal, Type.Unknown, Stats(65,70,60,65,65,115)));
        pokedex.push(PokemonData(54, Type.Water, Type.Unknown, Stats(50,52,48,65,50,55)));
        pokedex.push(PokemonData(55, Type.Water, Type.Unknown, Stats(80,82,78,95,80,85)));
        pokedex.push(PokemonData(56, Type.Fighting, Type.Unknown, Stats(40,80,35,35,45,70)));
        pokedex.push(PokemonData(57, Type.Fighting, Type.Unknown, Stats(65,105,60,60,70,95)));
        pokedex.push(PokemonData(58, Type.Fire, Type.Unknown, Stats(55,70,45,70,50,60)));
        pokedex.push(PokemonData(59, Type.Fire, Type.Unknown, Stats(90,110,80,100,80,95)));
        pokedex.push(PokemonData(60, Type.Water, Type.Unknown, Stats(40,50,40,40,40,90)));
        pokedex.push(PokemonData(61, Type.Water, Type.Unknown, Stats(65,65,65,50,50,90)));
        pokedex.push(PokemonData(62, Type.Water, Type.Fighting, Stats(90,95,95,70,90,70)));
        pokedex.push(PokemonData(63, Type.Psychic, Type.Unknown, Stats(25,20,15,105,55,90)));
        pokedex.push(PokemonData(64, Type.Psychic, Type.Unknown, Stats(40,35,30,120,70,105)));
        pokedex.push(PokemonData(65, Type.Psychic, Type.Unknown, Stats(55,50,45,135,95,120)));
        pokedex.push(PokemonData(66, Type.Fighting, Type.Unknown, Stats(70,80,50,35,35,35)));
        pokedex.push(PokemonData(67, Type.Fighting, Type.Unknown, Stats(80,100,70,50,60,45)));
        pokedex.push(PokemonData(68, Type.Fighting, Type.Unknown, Stats(90,130,80,65,85,55)));
        pokedex.push(PokemonData(69, Type.Grass, Type.Poison, Stats(50,75,35,70,30,40)));
        pokedex.push(PokemonData(70, Type.Grass, Type.Poison, Stats(65,90,50,85,45,55)));
        pokedex.push(PokemonData(71, Type.Grass, Type.Poison, Stats(80,105,65,100,70,70)));
        pokedex.push(PokemonData(72, Type.Water, Type.Poison, Stats(40,40,35,50,100,70)));
        pokedex.push(PokemonData(73, Type.Water, Type.Poison, Stats(80,70,65,80,120,100)));
        pokedex.push(PokemonData(74, Type.Rock, Type.Ground, Stats(40,80,100,30,30,20)));
        pokedex.push(PokemonData(75, Type.Rock, Type.Ground, Stats(55,95,115,45,45,35)));
        pokedex.push(PokemonData(76, Type.Rock, Type.Ground, Stats(80,120,130,55,65,45)));
        pokedex.push(PokemonData(77, Type.Fire, Type.Unknown, Stats(50,85,55,65,65,90)));
        pokedex.push(PokemonData(78, Type.Fire, Type.Unknown, Stats(65,100,70,80,80,105)));
        pokedex.push(PokemonData(79, Type.Water, Type.Psychic, Stats(90,65,65,40,40,15)));
        pokedex.push(PokemonData(80, Type.Water, Type.Psychic, Stats(95,75,110,100,80,30)));
        pokedex.push(PokemonData(81, Type.Electric, Type.Steel, Stats(25,35,70,95,55,45)));
        pokedex.push(PokemonData(82, Type.Electric, Type.Steel, Stats(50,60,95,120,70,70)));
        pokedex.push(PokemonData(83, Type.Normal, Type.Flying, Stats(52,90,55,58,62,60)));
        pokedex.push(PokemonData(84, Type.Normal, Type.Flying, Stats(35,85,45,35,35,75)));
        pokedex.push(PokemonData(85, Type.Normal, Type.Flying, Stats(60,110,70,60,60,110)));
        pokedex.push(PokemonData(86, Type.Water, Type.Unknown, Stats(65,45,55,45,70,45)));
        pokedex.push(PokemonData(87, Type.Water, Type.Ice, Stats(90,70,80,70,95,70)));
        pokedex.push(PokemonData(88, Type.Poison, Type.Unknown, Stats(80,80,50,40,50,25)));
        pokedex.push(PokemonData(89, Type.Poison, Type.Unknown, Stats(105,105,75,65,100,50)));
        pokedex.push(PokemonData(90, Type.Water, Type.Unknown, Stats(30,65,100,45,25,40)));
        pokedex.push(PokemonData(91, Type.Water, Type.Ice, Stats(50,95,180,85,45,70)));
        pokedex.push(PokemonData(92, Type.Ghost, Type.Poison, Stats(30,35,30,100,35,80)));
        pokedex.push(PokemonData(93, Type.Ghost, Type.Poison, Stats(45,50,45,115,55,95)));
        pokedex.push(PokemonData(94, Type.Ghost, Type.Poison, Stats(60,65,60,130,75,110)));
        pokedex.push(PokemonData(95, Type.Rock, Type.Ground, Stats(35,45,160,30,45,70)));
        pokedex.push(PokemonData(96, Type.Psychic, Type.Unknown, Stats(60,48,45,43,90,42)));
        pokedex.push(PokemonData(97, Type.Psychic, Type.Unknown, Stats(85,73,70,73,115,67)));
        pokedex.push(PokemonData(98, Type.Water, Type.Unknown, Stats(30,105,90,25,25,50)));
        pokedex.push(PokemonData(99, Type.Water, Type.Unknown, Stats(55,130,115,50,50,75)));
        pokedex.push(PokemonData(100, Type.Electric, Type.Unknown, Stats(40,30,50,55,55,100)));
        pokedex.push(PokemonData(101, Type.Electric, Type.Unknown, Stats(60,50,70,80,80,150)));
        pokedex.push(PokemonData(102, Type.Grass, Type.Psychic, Stats(60,40,80,60,45,40)));
        pokedex.push(PokemonData(103, Type.Grass, Type.Psychic, Stats(95,95,85,125,75,55)));
        pokedex.push(PokemonData(104, Type.Ground, Type.Unknown, Stats(50,50,95,40,50,35)));
        pokedex.push(PokemonData(105, Type.Ground, Type.Unknown, Stats(60,80,110,50,80,45)));
        pokedex.push(PokemonData(106, Type.Fighting, Type.Unknown, Stats(50,120,53,35,110,87)));
        pokedex.push(PokemonData(107, Type.Fighting, Type.Unknown, Stats(50,105,79,35,110,76)));
        pokedex.push(PokemonData(108, Type.Normal, Type.Unknown, Stats(90,55,75,60,75,30)));
        pokedex.push(PokemonData(109, Type.Poison, Type.Unknown, Stats(40,65,95,60,45,35)));
        pokedex.push(PokemonData(110, Type.Poison, Type.Unknown, Stats(65,90,120,85,70,60)));
        pokedex.push(PokemonData(111, Type.Ground, Type.Rock, Stats(80,85,95,30,30,25)));
        pokedex.push(PokemonData(112, Type.Ground, Type.Rock, Stats(105,130,120,45,45,40)));
        pokedex.push(PokemonData(113, Type.Normal, Type.Unknown, Stats(250,5,5,35,105,50)));
        pokedex.push(PokemonData(114, Type.Grass, Type.Unknown, Stats(65,55,115,100,40,60)));
        pokedex.push(PokemonData(115, Type.Normal, Type.Unknown, Stats(105,95,80,40,80,90)));
        pokedex.push(PokemonData(116, Type.Water, Type.Unknown, Stats(30,40,70,70,25,60)));
        pokedex.push(PokemonData(117, Type.Water, Type.Unknown, Stats(55,65,95,95,45,85)));
        pokedex.push(PokemonData(118, Type.Water, Type.Unknown, Stats(45,67,60,35,50,63)));
        pokedex.push(PokemonData(119, Type.Water, Type.Unknown, Stats(80,92,65,65,80,68)));
        pokedex.push(PokemonData(120, Type.Water, Type.Unknown, Stats(30,45,55,70,55,85)));
        pokedex.push(PokemonData(121, Type.Water, Type.Psychic, Stats(60,75,85,100,85,115)));
        pokedex.push(PokemonData(122, Type.Psychic, Type.Fairy, Stats(40,45,65,100,120,90)));
        pokedex.push(PokemonData(123, Type.Bug, Type.Flying, Stats(70,110,80,55,80,105)));
        pokedex.push(PokemonData(124, Type.Ice, Type.Psychic, Stats(65,50,35,115,95,95)));
        pokedex.push(PokemonData(125, Type.Electric, Type.Unknown, Stats(65,83,57,95,85,105)));
        pokedex.push(PokemonData(126, Type.Fire, Type.Unknown, Stats(65,95,57,100,85,93)));
        pokedex.push(PokemonData(127, Type.Bug, Type.Unknown, Stats(65,125,100,55,70,85)));
        pokedex.push(PokemonData(128, Type.Normal, Type.Unknown, Stats(75,100,95,40,70,110)));
        pokedex.push(PokemonData(129, Type.Water, Type.Unknown, Stats(20,10,55,15,20,80)));
        pokedex.push(PokemonData(130, Type.Water, Type.Flying, Stats(95,125,79,60,100,81)));
        pokedex.push(PokemonData(131, Type.Water, Type.Ice, Stats(130,85,80,85,95,60)));
        pokedex.push(PokemonData(132, Type.Normal, Type.Unknown, Stats(48,48,48,48,48,48)));
        pokedex.push(PokemonData(133, Type.Normal, Type.Unknown, Stats(55,55,50,45,65,55)));
        pokedex.push(PokemonData(134, Type.Water, Type.Unknown, Stats(130,65,60,110,95,65)));
        pokedex.push(PokemonData(135, Type.Electric, Type.Unknown, Stats(65,65,60,110,95,130)));
        pokedex.push(PokemonData(136, Type.Fire, Type.Unknown, Stats(65,130,60,95,110,65)));
        pokedex.push(PokemonData(137, Type.Normal, Type.Unknown, Stats(65,60,70,85,75,40)));
        pokedex.push(PokemonData(138, Type.Rock, Type.Water, Stats(35,40,100,90,55,35)));
        pokedex.push(PokemonData(139, Type.Rock, Type.Water, Stats(70,60,125,115,70,55)));
        pokedex.push(PokemonData(140, Type.Rock, Type.Water, Stats(30,80,90,55,45,55)));
        pokedex.push(PokemonData(141, Type.Rock, Type.Water, Stats(60,115,105,65,70,80)));
        pokedex.push(PokemonData(142, Type.Rock, Type.Flying, Stats(80,105,65,60,75,130)));
        pokedex.push(PokemonData(143, Type.Normal, Type.Unknown, Stats(160,110,65,65,110,30)));
        pokedex.push(PokemonData(144, Type.Ice, Type.Flying, Stats(90,85,100,95,125,85)));
        pokedex.push(PokemonData(145, Type.Electric, Type.Flying, Stats(90,90,85,125,90,100)));
        pokedex.push(PokemonData(146, Type.Fire, Type.Flying, Stats(90,100,90,125,85,90)));
        pokedex.push(PokemonData(147, Type.Dragon, Type.Unknown, Stats(41,64,45,50,50,50)));
        pokedex.push(PokemonData(148, Type.Dragon, Type.Unknown, Stats(61,84,65,70,70,70)));
        pokedex.push(PokemonData(149, Type.Dragon, Type.Flying, Stats(91,134,95,100,100,80)));
        pokedex.push(PokemonData(150, Type.Psychic, Type.Unknown, Stats(106,110,90,154,90,130)));
        pokedex.push(PokemonData(151, Type.Psychic, Type.Unknown, Stats(100,100,100,100,100,100)));
    }

    function generateNewPokemon() internal view returns(Pokemon memory pokemon) {
        bytes32 rng = keccak256(abi.encodePacked(block.timestamp, block.difficulty));

        while(uint256(rng & bytes32(uint256(0xFF)))  > pokedex.length - 1) {
            rng = bytes32(keccak256(abi.encodePacked(rng)));
        }

        uint8 id       = uint8(uint256(rng & bytes32(uint256(0xFF)))            ) + 1;
        bool gender    = uint8(uint256(rng & bytes32(uint256(0x100)))           / (2 ** 8)) == 1;
        uint8 hp       = uint8(uint256(rng & bytes32(uint256(0x3E00)))          / (2 ** 9));
        uint8 atk      = uint8(uint256(rng & bytes32(uint256(0x7C000)))         / (2 ** 14));
        uint8 def      = uint8(uint256(rng & bytes32(uint256(0xF80000)))        / (2 ** 19));
        uint8 spAtk    = uint8(uint256(rng & bytes32(uint256(0x1F000000)))      / (2 ** 24));
        uint8 spDef    = uint8(uint256(rng & bytes32(uint256(0x3E0000000)))     / (2 ** 29));
        uint8 speed    = uint8(uint256(rng & bytes32(uint256(0x7C00000000)))    / (2 ** 34));
        bool isShiny   = uint8(uint256(rng & bytes32(uint256(0x1FF8000000000))) / (2 ** 39)) == 0;


        PokemonData memory data = pokedex[id+1];
        pokemon = Pokemon(id, gender ? Gender.Male : Gender.Female, isShiny,
            Stats(hp, atk, def, spAtk, spDef, speed),
            Stats(
                calculateHP(data.base.hp, hp, 100),
                calculateStat(data.base.atk  , atk  , 100),
                calculateStat(data.base.def  , def  , 100),
                calculateStat(data.base.spAtk, spAtk, 100),
                calculateStat(data.base.spDef, spDef, 100),
                calculateStat(data.base.speed, speed, 100)
            )
        );
    }

    function calculateHP(uint256 base, uint256 iv, uint256 level) private pure returns(uint8) {
        return uint8(level + 10 + ((base + iv) * 2 * level) / 100);
    }

    function calculateStat(uint256 base, uint256 iv, uint256 level) private pure returns(uint8) {
        return uint8(5 + ((base + iv) * 2 * level) / 100);
    }

    function getPokemonData(uint8 id) public view returns(PokemonData memory) {
        return pokedex[id];
    }
}
