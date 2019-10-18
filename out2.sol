
// File: contracts/Battles/PlasmaTurnGame.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

interface PlasmaTurnGame {
    function validateStartState(bytes calldata /*state*/) external pure;
    function validateTurnTransition(bytes calldata /*oldstate*/, uint /*oldturnNum*/, bytes calldata /*newstate*/) external pure;
    function winner(bytes calldata /*state*/, uint /*turnNum*/, address /*player*/, address /*opponent*/) external pure returns (address);
    function isOver(bytes calldata /*state*/, uint /*turnNum*/) external pure returns (bool);
    function mover(bytes calldata /*state*/, uint /*turnNum*/, address /*player*/, address /*opponent*/) external pure returns (address);
    function eventStartState(bytes calldata /*state*/, address /*player*/, address /*opponent*/) external;
}

// File: contracts/Libraries/ECVerify.sol

pragma solidity ^0.5.2;


library ECVerify {

    enum SignatureMode {
        EIP712,
        GETH,
        TREZOR
    }

    function recover(bytes32 h, bytes memory signature) internal pure returns (address) {
        // 66 bytes since the first byte is used to determine SignatureMode
        // 65 bytes or 0x0... EIP712
        // 0x1... GETH
        // 0x2... TREZOR
        require(signature.length == 65 || signature.length == 66, "Signature lenght is invalid");
        SignatureMode mode;

        bytes32 hash = h;
        uint8 v;
        bytes32 r;
        bytes32 s;

        uint8 offset = 1;
        if(signature.length == 65) {
            offset = 0;
            mode = SignatureMode.EIP712;
        } else {
            mode = SignatureMode(uint8(signature[0]));
        }
        assembly {
            r := mload(add(signature, add(32,offset)))
            s := mload(add(signature, add(64,offset)))
            v := and(mload(add(signature, add(65, offset))), 255)
        }

        if (mode == SignatureMode.GETH) {
            hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        } else if (mode == SignatureMode.TREZOR) {
            hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n\x20", hash));
        }

        return ecrecover(
            hash,
            v,
            r,
            s);
    }

    function ecverify(bytes32 hash, bytes memory sig, address signer) internal pure returns (bool) {
        return signer == recover(hash, sig);
    }

}

// File: contracts/Battles/State.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;



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
        return game(state).mover(state.gameAttributes, state.turnNum, state.participants[0], state.participants[1]);
    }

    function winner(StateStruct memory state) public pure returns (address) {
        return game(state).winner(state.gameAttributes, state.turnNum, state.participants[0], state.participants[1]);
    }

    function isOver(StateStruct memory state) public pure returns (bool) {
        return game(state).isOver(state.gameAttributes, state.turnNum);
    }

    function validateGameTransition(StateStruct memory state, StateStruct memory newState) public pure {
        game(state).validateTurnTransition(state.gameAttributes, state.turnNum, newState.gameAttributes);
    }

    function eventStartState(StateStruct memory initialState) public {
        game(initialState).eventStartState(initialState.gameAttributes, initialState.participants[0], initialState.participants[1]);
    }

    //State is signed by mover
    function requireSignature(StateStruct memory state, bytes memory signature) public pure {
        require(
            keccak256(abi.encode(state)).ecverify(signature, mover(state)),
            "mover must have signed state"
        );
    }
}

// File: contracts/Battles/Rules.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;



library Rules {
    using State for State.StateStruct;

    struct Challenge {
        State.StateStruct state;
        uint32 expirationTime;
        address winner;
    }

    function validateStartState(
        State.StateStruct memory state,
        address player,
        address opponent,
        bytes32 initialArgumentsHash
    ) internal pure {
       require(state.turnNum == 0, "First turn must be 0");
       require(state.participants[0] == player, "State player is incorrect");
       require(state.participants[1] == opponent, "State opponent is incorrect");
       require(initialArgumentsHash == keccak256(state.gameAttributes), "Initial states does not match");
    }
    
    function validateTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal pure {
        require(
            toState.channelId == fromState.channelId,
            "Invalid transition: channelId must match on toState"
        );
        require(
            toState.turnNum == fromState.turnNum + 1,
            "Invalid transition: turnNum must increase by 1"
        );

        require(
            toState.channelType == fromState.channelType,
            "ChannelType must remain the same"
        );

        require(
            toState.participants[0] == fromState.participants[0]
            && toState.participants[1] == fromState.participants[1],
            "Players must remain the same"
        );

        fromState.validateGameTransition(toState);
    }


    function validGameTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal pure {
        fromState.validateGameTransition(toState);
    }

    function validateSignedTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState,
        bytes[] memory signatures
    ) internal pure {
        // states must be signed by the appropriate participant
        fromState.requireSignature(signatures[0]);
        toState.requireSignature(signatures[1]);

        return validateTransition(fromState, toState);
    }

    function validateRefute(
        State.StateStruct memory challengeState,
        State.StateStruct memory refutationState,
        bytes memory signature
    ) internal pure {
        require(
            refutationState.turnNum > challengeState.turnNum,
            "the refutationState must have a higher nonce"
        );
        require(
            refutationState.mover() == challengeState.mover(),
            "refutationState must have same mover as challengeState"
        );
        // ... and be signed (by that mover)
        refutationState.requireSignature(signature);
    }

    function validateRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory nextState,
        bytes memory signature
    ) internal pure {
        // check that the challengee's signature matches
        nextState.requireSignature(signature);
        validateTransition(challengeState, nextState);
    }

    function validateAlternativeRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures
    ) internal pure {

        // checking the alternative state:
        require(
            challengeState.channelId == alternativeState.channelId,
            "alternativeState must have the right channel"
        );
        
        require(
            challengeState.turnNum == alternativeState.turnNum,
            "alternativeState must have the same nonce as the challenge state"
        );
        
        // .. it must be signed (by the challenger)
        alternativeState.requireSignature(signatures[0]);

        // checking the nextState:
        // .. it must be signed (my the challengee)
        nextState.requireSignature(signatures[1]);

        validateTransition(alternativeState, nextState);
    }
}

// File: contracts/Libraries/ChallengeLib.sol

// Copyright Loom Network 2018 - All rights reserved, Dual licensed on GPLV3
// Learn more about Loom DappChains at https://loomx.io
// All derivitive works of this code must incluse this copyright header on every file

pragma solidity ^0.5.2;

/**
* @title ChallengeLib
*
* ChallengeLib is a helper library for constructing challenges
*/

library ChallengeLib {
    struct Challenge {
        address owner;
        address challenger;
        bytes32 txHash;
        uint256 challengingBlockNumber;
    }

    function contains(Challenge[] storage _array, bytes32 txHash) internal view returns (bool) {
        int index = indexOf(_array, txHash);
        return index != -1;
    }

    function remove(Challenge[] storage _array, bytes32 txHash) internal returns (bool) {
        int index = indexOf(_array, txHash);
        if (index == -1) {
            return false; // Tx not in challenge arraey
        }
        // Replace element with last element
        Challenge memory lastChallenge = _array[_array.length - 1];
        _array[uint(index)] = lastChallenge;

        // Reduce array length
        delete _array[_array.length - 1];
        _array.length -= 1;
        return true;
    }

    function indexOf(Challenge[] storage _array, bytes32 txHash) internal view returns (int) {
        for (uint i = 0; i < _array.length; i++) {
            if (_array[i].txHash == txHash) {
                return int(i);
            }
        }
        return -1;
    }
}

// File: contracts/Battles/Adjudicator.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;





library Adjudicator {

    using State for State.StateStruct;
    using Adjudicator for FMChannel;

    enum ChannelState { INITIATED, FUNDED, SUSPENDED, CLOSED, WITHDRAWN }

    //Force Move Channel
    struct FMChannel {
        uint256 channelId;
        address channelType;
        uint256 stake;
        address[2] players;
        bytes32 initialArgumentsHash;
        ChannelState state;
        Rules.Challenge forceMoveChallenge;
        ChallengeLib.Challenge plasmaChallenge;
    }

    uint constant CHALLENGE_DURATION = 10 * 1 minutes;

    function forceFirstMove(
        FMChannel storage channel,
        State.StateStruct memory initialState,
        address issuer
    )
    internal
    withoutCurrentChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    matchId(channel, initialState)
    {
        Rules.validateStartState(initialState, channel.players[0], channel.players[1], channel.initialArgumentsHash);
        createChallenge(channel, uint32(now + CHALLENGE_DURATION), initialState, issuer);
    }

    function forceMove(
        FMChannel storage channel,
        State.StateStruct memory fromState,
        State.StateStruct memory toState,
        address issuer,
        bytes[] memory signatures
    )
    internal
    withoutCurrentChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    matchId(channel, fromState)
    {
        if(signatures[0].length == 0 ) {
            Rules.validateStartState(fromState, channel.players[0], channel.players[1], channel.initialArgumentsHash);
            toState.requireSignature(signatures[1]);
            Rules.validateTransition(fromState, toState);
        } else {
            Rules.validateSignedTransition(fromState, toState, signatures);
        }
        createChallenge(channel, uint32(now + CHALLENGE_DURATION), toState, issuer);
    }

    //Respond is used to cancel your opponent's challenge
    function respondWithMove(
        FMChannel storage channel,
        State.StateStruct memory nextState,
        bytes memory signature)
    internal
    withActiveChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    {
        nextState.requireSignature(signature);
        Rules.validateTransition(channel.forceMoveChallenge.state, nextState);
        cancelCurrentChallenge(channel);
    }

    function alternativeRespondWithMove(
        FMChannel storage channel,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures
    )
    public
    withActiveChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    {
        Rules.validateAlternativeRespondWithMove(channel.forceMoveChallenge.state, alternativeState, nextState, signatures);
        //TODO check if this should create a new challenge
        cancelCurrentChallenge(channel);
    }

    //TODO revise this
    function refute(
        FMChannel storage channel,
        State.StateStruct memory refutingState,
        bytes memory signature
    )
    public
    withActiveChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    {
        Rules.validateRefute(channel.forceMoveChallenge.state, refutingState, signature);
        cancelCurrentChallenge(channel);
    }

    function conclude(
        FMChannel storage channel,
        State.StateStruct memory penultimateState,
        State.StateStruct memory ultimateState,
        bytes[] memory signatures
    )
    internal
    withoutActiveChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    matchId(channel, penultimateState)
    {

        Rules.validateSignedTransition(penultimateState, ultimateState, signatures);
        require(ultimateState.isOver(), "Ultimate State must be a final state");

        //Create an expired challenge that acts as the final state
        createChallenge(channel, uint32(now), ultimateState, ultimateState.winner());
    }

    function createChallenge(
        FMChannel storage channel,
        uint32 expirationTime,
        State.StateStruct memory state,
        address challengeIssuer)
    private {
        channel.forceMoveChallenge.state = state;
        channel.forceMoveChallenge.expirationTime = expirationTime;

        if(state.isOver()) {
            channel.forceMoveChallenge.winner = state.winner();
        } else {
            channel.forceMoveChallenge.winner = challengeIssuer;
        }
    }

    function cancelCurrentChallenge(FMChannel storage channel) private{
        channel.forceMoveChallenge.expirationTime = 0;
    }

    function currentChallengePresent(FMChannel storage channel) public view returns (bool) {
        return channel.forceMoveChallenge.expirationTime > 0;
    }

    function activeChallengePresent(FMChannel storage channel) public view returns (bool) {
        return (channel.forceMoveChallenge.expirationTime > now);
    }

    function expiredChallengePresent(FMChannel storage channel) public view returns (bool) {
        return channel.currentChallengePresent() && !channel.activeChallengePresent();
    }

    // Modifiers
    modifier withCurrentChallenge(FMChannel storage channel) {
        require(channel.currentChallengePresent(), "Current challenge must be present");
        _;
    }

    modifier withoutCurrentChallenge(FMChannel storage channel) {
        require(!channel.currentChallengePresent(), "current challenge must not be present");
        _;
    }

    modifier withActiveChallenge(FMChannel storage channel) {
        require(channel.activeChallengePresent(), "active challenge must be present");
        _;
    }

    modifier withoutActiveChallenge(FMChannel storage channel) {
        require(!channel.activeChallengePresent(), "active challenge must be present");
        _;
    }

    modifier whenState(FMChannel storage channel, ChannelState state) {
        require(channel.state == state, "Incorrect channel state");
        _;
    }

    modifier matchId(FMChannel storage channel, State.StateStruct memory state) {
        require(channel.channelId == state.channelId, "Channel's channelId must match the state's channelId");
        _;
    }
}

// File: openzeppelin-solidity/contracts/math/SafeMath.sol

pragma solidity ^0.5.2;

/**
 * @title SafeMath
 * @dev Unsigned math operations with safety checks that revert on error
 */
library SafeMath {
    /**
     * @dev Multiplies two unsigned integers, reverts on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
     * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two unsigned integers, reverts on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
     * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
     * reverts when dividing by zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}

// File: openzeppelin-solidity/contracts/drafts/Counters.sol

pragma solidity ^0.5.2;


/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented or decremented by one. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids
 *
 * Include with `using Counters for Counters.Counter;`
 * Since it is not possible to overflow a 256 bit integer with increments of one, `increment` can skip the SafeMath
 * overflow check, thereby saving gas. This does assume however correct usage, in that the underlying `_value` is never
 * directly accessed.
 */
library Counters {
    using SafeMath for uint256;

    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        counter._value += 1;
    }

    function decrement(Counter storage counter) internal {
        counter._value = counter._value.sub(1);
    }
}

// File: contracts/Battles/PlasmaChannelManager.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;








//TODO add global timeout for channel
//Plasma Channel Manager
contract PlasmaCM {
    //events
    event ChannelInitiated(uint channelId, address indexed creator, address indexed opponent, address channelType);
    event ChannelFunded(uint channelId, address indexed creator, address indexed opponent, address channelType);

    //events

    using Adjudicator for Adjudicator.FMChannel;
    using Counters for Counters.Counter;
    using ECVerify for bytes32;
    using State for State.StateStruct;

    mapping (uint => Adjudicator.FMChannel) channels;

    Counters.Counter channelCounter;

    uint256 constant DEPOSIT_AMOUNT = 0.1 ether;
    mapping (address => Counters.Counter) openChannels;
    mapping (address => bool) deposited;

    function () external payable {
        revert("Please send funds using the FundChannel or makeDeposit method");
    }

    //TODO close unfunded channel
    function initiateChannel(
        address channelType,
        address opponent,
        uint stake,
        bytes memory initialGameAttributes
    ) public payable Payment(stake) hasDeposit {

        ((PlasmaTurnGame)(channelType)).validateStartState(initialGameAttributes);
        channelCounter.increment();

        uint channelId = channelCounter.current();

        address[2] memory addresses;
        addresses[0] = msg.sender;
        addresses[1] = opponent;

        openChannels[msg.sender].increment();

        Rules.Challenge memory rchallenge;
        ChallengeLib.Challenge memory cchallenge;

        channels[channelId] = Adjudicator.FMChannel(
            channelId,
            channelType,
            stake,
            addresses,
            keccak256(initialGameAttributes),
            Adjudicator.ChannelState.INITIATED,
            rchallenge,
            cchallenge
        );


        emit ChannelInitiated(channelId, msg.sender, opponent, channelType);
    }

    function fundChannel(
        uint channelId,
        bytes memory initialGameAttributes
    ) public payable channelExists(channelId) hasDeposit {
        Adjudicator.FMChannel storage channel = channels[channelId];

        require(channel.state == Adjudicator.ChannelState.INITIATED, "Channel is already funded");
        require(channel.players[1] == msg.sender, "Sender is not participant of this channel");
        require(channel.stake == msg.value, "Payment must be equal to channel stake");
        require(channel.initialArgumentsHash == keccak256(abi.encode(initialGameAttributes)), "Initial state does not match");
        channel.state = Adjudicator.ChannelState.FUNDED;

        openChannels[msg.sender].increment();

        //TODO emit
        emit ChannelFunded(channel.channelId, channel.players[0], channel.players[1], channel.channelType);
        ((PlasmaTurnGame)(channel.channelType)).eventStartState(initialGameAttributes, channel.players[0], channel.players[1]);
    }

    function makeDeposit() external payable Payment(DEPOSIT_AMOUNT) {
        require(!deposited[msg.sender], "Sender already did a deposit");
        deposited[msg.sender] = true;
    }

    function retrievedDeposit() external payable hasDeposit {
        require(openChannels[msg.sender].current() == 0, "Sender has an open channel");
        deposited[msg.sender] = false;

        msg.sender.transfer(DEPOSIT_AMOUNT);
    }

    function forceFirstMove(
        uint channelId,
        State.StateStruct memory initialState) public channelExists(channelId) hasDeposit {
        channels[channelId].forceFirstMove(initialState, msg.sender);
    }

    function forceMove(
        uint channelId,
        State.StateStruct memory fromState,
        State.StateStruct memory nextState,
        bytes[] memory signatures)
    public channelExists(channelId) hasDeposit {

        channels[channelId].forceMove(fromState, nextState, msg.sender, signatures);
    }

    function respondWithMove(
        uint channelId,
        State.StateStruct memory nextState,
        bytes memory signature)
    public channelExists(channelId) hasDeposit {

        channels[channelId].respondWithMove(nextState, signature);
    }

    function alternativeRespondWithMove(
        uint channelId,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures)
    public channelExists(channelId) hasDeposit {

        channels[channelId].alternativeRespondWithMove(alternativeState, nextState, signatures);
    }

    function conclude(
        uint channelId,
        State.StateStruct memory prevState,
        State.StateStruct memory lastState,
        bytes[] memory signatures)
        public channelExists(channelId) hasDeposit {

        Adjudicator.FMChannel storage channel = channels[channelId];
        channel.conclude(prevState, lastState, signatures);
        channel.state = Adjudicator.ChannelState.CLOSED;
        //TODO emit
    }

    function withdraw(uint channelId) external channelExists(channelId) {

        Adjudicator.FMChannel storage channel = channels[channelId];
        require(channel.state == Adjudicator.ChannelState.CLOSED, "Channel must be closed");
        channel.state = Adjudicator.ChannelState.WITHDRAWN;

        openChannels[channel.players[0]].decrement();
        openChannels[channel.players[1]].decrement();

        msg.sender.transfer(channel.stake * 2);
        //TODO emit
    }


    ///
    //CHALLENGES
    ///

    //modifiers
    modifier Payment(uint stake) {
        require(stake > 0,"Stake must be greater than 0");
        require(stake == msg.value, "Invalid Payment amount");
        _;
    }

    modifier channelExists(uint channelId) {
        require(channels[channelId].channelId > 0, "Channel has not yet been created");
        _;
    }

    modifier hasDeposit() {
        require(deposited[msg.sender], "You must make a deposit to use the Game Channels");
        _;
    }
}

// File: contracts/Battles/PlasmaTurnGame.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

interface PlasmaTurnGame {
    function validateStartState(bytes calldata /*state*/) external pure;
    function validateTurnTransition(bytes calldata /*oldstate*/, uint /*oldturnNum*/, bytes calldata /*newstate*/) external pure;
    function winner(bytes calldata /*state*/, uint /*turnNum*/, address /*player*/, address /*opponent*/) external pure returns (address);
    function isOver(bytes calldata /*state*/, uint /*turnNum*/) external pure returns (bool);
    function mover(bytes calldata /*state*/, uint /*turnNum*/, address /*player*/, address /*opponent*/) external pure returns (address);
    function eventStartState(bytes calldata /*state*/, address /*player*/, address /*opponent*/) external;
}

// File: contracts/Libraries/ECVerify.sol

pragma solidity ^0.5.2;


library ECVerify {

    enum SignatureMode {
        EIP712,
        GETH,
        TREZOR
    }

    function recover(bytes32 h, bytes memory signature) internal pure returns (address) {
        // 66 bytes since the first byte is used to determine SignatureMode
        // 65 bytes or 0x0... EIP712
        // 0x1... GETH
        // 0x2... TREZOR
        require(signature.length == 65 || signature.length == 66, "Signature lenght is invalid");
        SignatureMode mode;

        bytes32 hash = h;
        uint8 v;
        bytes32 r;
        bytes32 s;

        uint8 offset = 1;
        if(signature.length == 65) {
            offset = 0;
            mode = SignatureMode.EIP712;
        } else {
            mode = SignatureMode(uint8(signature[0]));
        }
        assembly {
            r := mload(add(signature, add(32,offset)))
            s := mload(add(signature, add(64,offset)))
            v := and(mload(add(signature, add(65, offset))), 255)
        }

        if (mode == SignatureMode.GETH) {
            hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        } else if (mode == SignatureMode.TREZOR) {
            hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n\x20", hash));
        }

        return ecrecover(
            hash,
            v,
            r,
            s);
    }

    function ecverify(bytes32 hash, bytes memory sig, address signer) internal pure returns (bool) {
        return signer == recover(hash, sig);
    }

}

// File: contracts/Battles/State.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;



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
        return game(state).mover(state.gameAttributes, state.turnNum, state.participants[0], state.participants[1]);
    }

    function winner(StateStruct memory state) public pure returns (address) {
        return game(state).winner(state.gameAttributes, state.turnNum, state.participants[0], state.participants[1]);
    }

    function isOver(StateStruct memory state) public pure returns (bool) {
        return game(state).isOver(state.gameAttributes, state.turnNum);
    }

    function validateGameTransition(StateStruct memory state, StateStruct memory newState) public pure {
        game(state).validateTurnTransition(state.gameAttributes, state.turnNum, newState.gameAttributes);
    }

    function eventStartState(StateStruct memory initialState) public {
        game(initialState).eventStartState(initialState.gameAttributes, initialState.participants[0], initialState.participants[1]);
    }

    //State is signed by mover
    function requireSignature(StateStruct memory state, bytes memory signature) public pure {
        require(
            keccak256(abi.encode(state)).ecverify(signature, mover(state)),
            "mover must have signed state"
        );
    }
}

// File: contracts/Battles/Rules.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;



library Rules {
    using State for State.StateStruct;

    struct Challenge {
        State.StateStruct state;
        uint32 expirationTime;
        address winner;
    }

    function validateStartState(
        State.StateStruct memory state,
        address player,
        address opponent,
        bytes32 initialArgumentsHash
    ) internal pure {
       require(state.turnNum == 0, "First turn must be 0");
       require(state.participants[0] == player, "State player is incorrect");
       require(state.participants[1] == opponent, "State opponent is incorrect");
       require(initialArgumentsHash == keccak256(state.gameAttributes), "Initial states does not match");
    }
    
    function validateTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal pure {
        require(
            toState.channelId == fromState.channelId,
            "Invalid transition: channelId must match on toState"
        );
        require(
            toState.turnNum == fromState.turnNum + 1,
            "Invalid transition: turnNum must increase by 1"
        );

        require(
            toState.channelType == fromState.channelType,
            "ChannelType must remain the same"
        );

        require(
            toState.participants[0] == fromState.participants[0]
            && toState.participants[1] == fromState.participants[1],
            "Players must remain the same"
        );

        fromState.validateGameTransition(toState);
    }


    function validGameTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState
    ) internal pure {
        fromState.validateGameTransition(toState);
    }

    function validateSignedTransition(
        State.StateStruct memory fromState,
        State.StateStruct memory toState,
        bytes[] memory signatures
    ) internal pure {
        // states must be signed by the appropriate participant
        fromState.requireSignature(signatures[0]);
        toState.requireSignature(signatures[1]);

        return validateTransition(fromState, toState);
    }

    function validateRefute(
        State.StateStruct memory challengeState,
        State.StateStruct memory refutationState,
        bytes memory signature
    ) internal pure {
        require(
            refutationState.turnNum > challengeState.turnNum,
            "the refutationState must have a higher nonce"
        );
        require(
            refutationState.mover() == challengeState.mover(),
            "refutationState must have same mover as challengeState"
        );
        // ... and be signed (by that mover)
        refutationState.requireSignature(signature);
    }

    function validateRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory nextState,
        bytes memory signature
    ) internal pure {
        // check that the challengee's signature matches
        nextState.requireSignature(signature);
        validateTransition(challengeState, nextState);
    }

    function validateAlternativeRespondWithMove(
        State.StateStruct memory challengeState,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures
    ) internal pure {

        // checking the alternative state:
        require(
            challengeState.channelId == alternativeState.channelId,
            "alternativeState must have the right channel"
        );
        
        require(
            challengeState.turnNum == alternativeState.turnNum,
            "alternativeState must have the same nonce as the challenge state"
        );
        
        // .. it must be signed (by the challenger)
        alternativeState.requireSignature(signatures[0]);

        // checking the nextState:
        // .. it must be signed (my the challengee)
        nextState.requireSignature(signatures[1]);

        validateTransition(alternativeState, nextState);
    }
}

// File: contracts/Libraries/ChallengeLib.sol

// Copyright Loom Network 2018 - All rights reserved, Dual licensed on GPLV3
// Learn more about Loom DappChains at https://loomx.io
// All derivitive works of this code must incluse this copyright header on every file

pragma solidity ^0.5.2;

/**
* @title ChallengeLib
*
* ChallengeLib is a helper library for constructing challenges
*/

library ChallengeLib {
    struct Challenge {
        address owner;
        address challenger;
        bytes32 txHash;
        uint256 challengingBlockNumber;
    }

    function contains(Challenge[] storage _array, bytes32 txHash) internal view returns (bool) {
        int index = indexOf(_array, txHash);
        return index != -1;
    }

    function remove(Challenge[] storage _array, bytes32 txHash) internal returns (bool) {
        int index = indexOf(_array, txHash);
        if (index == -1) {
            return false; // Tx not in challenge arraey
        }
        // Replace element with last element
        Challenge memory lastChallenge = _array[_array.length - 1];
        _array[uint(index)] = lastChallenge;

        // Reduce array length
        delete _array[_array.length - 1];
        _array.length -= 1;
        return true;
    }

    function indexOf(Challenge[] storage _array, bytes32 txHash) internal view returns (int) {
        for (uint i = 0; i < _array.length; i++) {
            if (_array[i].txHash == txHash) {
                return int(i);
            }
        }
        return -1;
    }
}

// File: contracts/Battles/Adjudicator.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;





library Adjudicator {

    using State for State.StateStruct;
    using Adjudicator for FMChannel;

    enum ChannelState { INITIATED, FUNDED, SUSPENDED, CLOSED, WITHDRAWN }

    //Force Move Channel
    struct FMChannel {
        uint256 channelId;
        address channelType;
        uint256 stake;
        address[2] players;
        bytes32 initialArgumentsHash;
        ChannelState state;
        Rules.Challenge forceMoveChallenge;
        ChallengeLib.Challenge plasmaChallenge;
    }

    uint constant CHALLENGE_DURATION = 10 * 1 minutes;

    function forceFirstMove(
        FMChannel storage channel,
        State.StateStruct memory initialState,
        address issuer
    )
    internal
    withoutCurrentChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    matchId(channel, initialState)
    {
        Rules.validateStartState(initialState, channel.players[0], channel.players[1], channel.initialArgumentsHash);
        createChallenge(channel, uint32(now + CHALLENGE_DURATION), initialState, issuer);
    }

    function forceMove(
        FMChannel storage channel,
        State.StateStruct memory fromState,
        State.StateStruct memory toState,
        address issuer,
        bytes[] memory signatures
    )
    internal
    withoutCurrentChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    matchId(channel, fromState)
    {
        if(signatures[0].length == 0 ) {
            Rules.validateStartState(fromState, channel.players[0], channel.players[1], channel.initialArgumentsHash);
            toState.requireSignature(signatures[1]);
            Rules.validateTransition(fromState, toState);
        } else {
            Rules.validateSignedTransition(fromState, toState, signatures);
        }
        createChallenge(channel, uint32(now + CHALLENGE_DURATION), toState, issuer);
    }

    //Respond is used to cancel your opponent's challenge
    function respondWithMove(
        FMChannel storage channel,
        State.StateStruct memory nextState,
        bytes memory signature)
    internal
    withActiveChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    {
        nextState.requireSignature(signature);
        Rules.validateTransition(channel.forceMoveChallenge.state, nextState);
        cancelCurrentChallenge(channel);
    }

    function alternativeRespondWithMove(
        FMChannel storage channel,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures
    )
    public
    withActiveChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    {
        Rules.validateAlternativeRespondWithMove(channel.forceMoveChallenge.state, alternativeState, nextState, signatures);
        //TODO check if this should create a new challenge
        cancelCurrentChallenge(channel);
    }

    //TODO revise this
    function refute(
        FMChannel storage channel,
        State.StateStruct memory refutingState,
        bytes memory signature
    )
    public
    withActiveChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    {
        Rules.validateRefute(channel.forceMoveChallenge.state, refutingState, signature);
        cancelCurrentChallenge(channel);
    }

    function conclude(
        FMChannel storage channel,
        State.StateStruct memory penultimateState,
        State.StateStruct memory ultimateState,
        bytes[] memory signatures
    )
    internal
    withoutActiveChallenge(channel)
    whenState(channel, ChannelState.FUNDED)
    matchId(channel, penultimateState)
    {

        Rules.validateSignedTransition(penultimateState, ultimateState, signatures);
        require(ultimateState.isOver(), "Ultimate State must be a final state");

        //Create an expired challenge that acts as the final state
        createChallenge(channel, uint32(now), ultimateState, ultimateState.winner());
    }

    function createChallenge(
        FMChannel storage channel,
        uint32 expirationTime,
        State.StateStruct memory state,
        address challengeIssuer)
    private {
        channel.forceMoveChallenge.state = state;
        channel.forceMoveChallenge.expirationTime = expirationTime;

        if(state.isOver()) {
            channel.forceMoveChallenge.winner = state.winner();
        } else {
            channel.forceMoveChallenge.winner = challengeIssuer;
        }
    }

    function cancelCurrentChallenge(FMChannel storage channel) private{
        channel.forceMoveChallenge.expirationTime = 0;
    }

    function currentChallengePresent(FMChannel storage channel) public view returns (bool) {
        return channel.forceMoveChallenge.expirationTime > 0;
    }

    function activeChallengePresent(FMChannel storage channel) public view returns (bool) {
        return (channel.forceMoveChallenge.expirationTime > now);
    }

    function expiredChallengePresent(FMChannel storage channel) public view returns (bool) {
        return channel.currentChallengePresent() && !channel.activeChallengePresent();
    }

    // Modifiers
    modifier withCurrentChallenge(FMChannel storage channel) {
        require(channel.currentChallengePresent(), "Current challenge must be present");
        _;
    }

    modifier withoutCurrentChallenge(FMChannel storage channel) {
        require(!channel.currentChallengePresent(), "current challenge must not be present");
        _;
    }

    modifier withActiveChallenge(FMChannel storage channel) {
        require(channel.activeChallengePresent(), "active challenge must be present");
        _;
    }

    modifier withoutActiveChallenge(FMChannel storage channel) {
        require(!channel.activeChallengePresent(), "active challenge must be present");
        _;
    }

    modifier whenState(FMChannel storage channel, ChannelState state) {
        require(channel.state == state, "Incorrect channel state");
        _;
    }

    modifier matchId(FMChannel storage channel, State.StateStruct memory state) {
        require(channel.channelId == state.channelId, "Channel's channelId must match the state's channelId");
        _;
    }
}

// File: openzeppelin-solidity/contracts/math/SafeMath.sol

pragma solidity ^0.5.2;

/**
 * @title SafeMath
 * @dev Unsigned math operations with safety checks that revert on error
 */
library SafeMath {
    /**
     * @dev Multiplies two unsigned integers, reverts on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
     * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two unsigned integers, reverts on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
     * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
     * reverts when dividing by zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}

// File: openzeppelin-solidity/contracts/drafts/Counters.sol

pragma solidity ^0.5.2;


/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented or decremented by one. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids
 *
 * Include with `using Counters for Counters.Counter;`
 * Since it is not possible to overflow a 256 bit integer with increments of one, `increment` can skip the SafeMath
 * overflow check, thereby saving gas. This does assume however correct usage, in that the underlying `_value` is never
 * directly accessed.
 */
library Counters {
    using SafeMath for uint256;

    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        counter._value += 1;
    }

    function decrement(Counter storage counter) internal {
        counter._value = counter._value.sub(1);
    }
}

// File: contracts/Battles/PlasmaChannelManager.sol

pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;








//TODO add global timeout for channel
//Plasma Channel Manager
contract PlasmaCM {
    //events
    event ChannelInitiated(uint channelId, address indexed creator, address indexed opponent, address channelType);
    event ChannelFunded(uint channelId, address indexed creator, address indexed opponent, address channelType);

    //events

    using Adjudicator for Adjudicator.FMChannel;
    using Counters for Counters.Counter;
    using ECVerify for bytes32;
    using State for State.StateStruct;

    mapping (uint => Adjudicator.FMChannel) channels;

    Counters.Counter channelCounter;

    uint256 constant DEPOSIT_AMOUNT = 0.1 ether;
    mapping (address => Counters.Counter) openChannels;
    mapping (address => bool) deposited;

    function () external payable {
        revert("Please send funds using the FundChannel or makeDeposit method");
    }

    //TODO close unfunded channel
    function initiateChannel(
        address channelType,
        address opponent,
        uint stake,
        bytes memory initialGameAttributes
    ) public payable Payment(stake) hasDeposit {

        ((PlasmaTurnGame)(channelType)).validateStartState(initialGameAttributes);
        channelCounter.increment();

        uint channelId = channelCounter.current();

        address[2] memory addresses;
        addresses[0] = msg.sender;
        addresses[1] = opponent;

        openChannels[msg.sender].increment();

        Rules.Challenge memory rchallenge;
        ChallengeLib.Challenge memory cchallenge;

        channels[channelId] = Adjudicator.FMChannel(
            channelId,
            channelType,
            stake,
            addresses,
            keccak256(initialGameAttributes),
            Adjudicator.ChannelState.INITIATED,
            rchallenge,
            cchallenge
        );


        emit ChannelInitiated(channelId, msg.sender, opponent, channelType);
    }

    function fundChannel(
        uint channelId,
        bytes memory initialGameAttributes
    ) public payable channelExists(channelId) hasDeposit {
        Adjudicator.FMChannel storage channel = channels[channelId];

        require(channel.state == Adjudicator.ChannelState.INITIATED, "Channel is already funded");
        require(channel.players[1] == msg.sender, "Sender is not participant of this channel");
        require(channel.stake == msg.value, "Payment must be equal to channel stake");
        require(channel.initialArgumentsHash == keccak256(abi.encode(initialGameAttributes)), "Initial state does not match");
        channel.state = Adjudicator.ChannelState.FUNDED;

        openChannels[msg.sender].increment();

        //TODO emit
        emit ChannelFunded(channel.channelId, channel.players[0], channel.players[1], channel.channelType);
        ((PlasmaTurnGame)(channel.channelType)).eventStartState(initialGameAttributes, channel.players[0], channel.players[1]);
    }

    function makeDeposit() external payable Payment(DEPOSIT_AMOUNT) {
        require(!deposited[msg.sender], "Sender already did a deposit");
        deposited[msg.sender] = true;
    }

    function retrievedDeposit() external payable hasDeposit {
        require(openChannels[msg.sender].current() == 0, "Sender has an open channel");
        deposited[msg.sender] = false;

        msg.sender.transfer(DEPOSIT_AMOUNT);
    }

    function forceFirstMove(
        uint channelId,
        State.StateStruct memory initialState) public channelExists(channelId) hasDeposit {
        channels[channelId].forceFirstMove(initialState, msg.sender);
    }

    function forceMove(
        uint channelId,
        State.StateStruct memory fromState,
        State.StateStruct memory nextState,
        bytes[] memory signatures)
    public channelExists(channelId) hasDeposit {

        channels[channelId].forceMove(fromState, nextState, msg.sender, signatures);
    }

    function respondWithMove(
        uint channelId,
        State.StateStruct memory nextState,
        bytes memory signature)
    public channelExists(channelId) hasDeposit {

        channels[channelId].respondWithMove(nextState, signature);
    }

    function alternativeRespondWithMove(
        uint channelId,
        State.StateStruct memory alternativeState,
        State.StateStruct memory nextState,
        bytes[] memory signatures)
    public channelExists(channelId) hasDeposit {

        channels[channelId].alternativeRespondWithMove(alternativeState, nextState, signatures);
    }

    function conclude(
        uint channelId,
        State.StateStruct memory prevState,
        State.StateStruct memory lastState,
        bytes[] memory signatures)
        public channelExists(channelId) hasDeposit {

        Adjudicator.FMChannel storage channel = channels[channelId];
        channel.conclude(prevState, lastState, signatures);
        channel.state = Adjudicator.ChannelState.CLOSED;
        //TODO emit
    }

    function withdraw(uint channelId) external channelExists(channelId) {

        Adjudicator.FMChannel storage channel = channels[channelId];
        require(channel.state == Adjudicator.ChannelState.CLOSED, "Channel must be closed");
        channel.state = Adjudicator.ChannelState.WITHDRAWN;

        openChannels[channel.players[0]].decrement();
        openChannels[channel.players[1]].decrement();

        msg.sender.transfer(channel.stake * 2);
        //TODO emit
    }


    ///
    //CHALLENGES
    ///

    //modifiers
    modifier Payment(uint stake) {
        require(stake > 0,"Stake must be greater than 0");
        require(stake == msg.value, "Invalid Payment amount");
        _;
    }

    modifier channelExists(uint channelId) {
        require(channels[channelId].channelId > 0, "Channel has not yet been created");
        _;
    }

    modifier hasDeposit() {
        require(deposited[msg.sender], "You must make a deposit to use the Game Channels");
        _;
    }
}
