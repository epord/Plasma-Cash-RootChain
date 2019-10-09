pragma solidity ^0.5.2
pragma experimental ABIEncoderV2;

import "./State.sol";
import "./Rules.sol";
import "./ForceMoveGame.sol";

contract SimpleAdjudicator {
    // SimpleAdjudicator can support exactly one force move game channel
    // between exactly two players.
    using State for State.StateStruct;

    address public fundedChannelId;

    Rules.Challenge currentChallenge;
    uint challengeDuration;

    event FundsReceived(uint amountReceived, address sender, uint adjudicatorBalance);

    constructor(address _fundedChannelId, uint256 _challengeDurationMinutes) public payable {
        fundedChannelId = _fundedChannelId;
        challengeDuration = _challengeDurationMinutes * 1 minutes;

        emit FundsReceived(msg.value, msg.sender, address(this).balance);
    }

    // allow funds to be sent to the contract
    function () external payable {
        emit FundsReceived(msg.value, msg.sender, address(this).balance);
    }

    function forceMove (State.StateStruct memory _fromState, State.StateStruct memory _toState, bytes[] calldata _signatures)
    public
    onlyWhenCurrentChallengeNotPresent
    {
        //
        require(
            _fromState.channelId() == fundedChannelId,
            "channelId must match the game supported by the channel"
        );

        require(
            Rules.validForceMove(_fromState, _toState, _signatures),
            "must be a valid force move"
        );

        createChallenge(uint32(now + challengeDuration), _toState);
    }

    function concludeAndWithdraw(
        State.StateStruct memory _penultimateState,
        State.StateStruct memory _ultimateState,
        address participant,
        bytes[] calldata _signatures //[_penultimateState.sig, _ultimateState.sig]
    ) public {
        if (!expiredChallengePresent()){
            //Challenge is overwritten with the last concluded state if conclusion proof is valid
            _conclude(
                _penultimateState,
                _ultimateState,
                _signatures
            );
        }

        require(
        // You can't compare memory bytes (eg _ultimateState) with
        // storage bytes (eg. currentChallenge.state)
            keccak256(abi.encode(_ultimateState)) == keccak256(abi.encode(currentChallenge.state)),
            "Game already concluded with a different conclusion proof"
        );

        withdraw();
    }

    function conclude(
        State.StateStruct memory _penultimateState,
        State.StateStruct memory _ultimateState,
        bytes[] memory _signatures)
    public onlyWhenGameOngoing
    {
        _conclude(_penultimateState,_ultimateState, _signatures);
    }

    event GameConcluded();
    function _conclude(
        State.StateStruct memory _penultimateState,
        State.StateStruct memory _ultimateState,
        bytes[] memory _signatures
    )
    internal
    {
        // channelId must match the game supported by the channel
        require(_penultimateState.channelId() == fundedChannelId);

        // must be a valid conclusion proof according to framework rules
        require(Rules.validConclusionProof(_penultimateState, _ultimateState, _signatures));

        // Create an expired challenge, (possibly) overwriting any existing challenge
        createChallenge(uint32(now), _ultimateState);
        emit GameConcluded();

    }

    //Refute is used to cancel your own challenge
    //TODO to delete
    event Refuted(State.StateStruct refutation);
    function refute(State.StateStruct memory _refutationState, bytes memory signature)
    public
    onlyWhenCurrentChallengeActive
    {
        // channelId must match the game supported by the channel
        require(
            fundedChannelId == _refutationState.channelId(),
            "channelId must match"
        );

        // must be a valid refute according to framework rules
        require(
            Rules.validRefute(currentChallenge.state, _refutationState, signature),
            "must be a valid refute"
        );

        cancelCurrentChallenge();

        emit Refuted(_refutationState);
    }

    //Respond is used to cancel your opponent's challenge
    event RespondedWithMove(State.StateStruct response);
    function respondWithMove(State.StateStruct memory _nextState, bytes signature)
    public
    onlyWhenCurrentChallengeActive
    {
        require(
            Rules.validRespondWithMove(currentChallenge.state, _nextState, signature),
            "must be valid respond with move according to the framework rules"
        );

        cancelCurrentChallenge();
        emit RespondedWithMove(_nextState);
    }

    //TODO shouldnt 2 states signed break everything?
    event RespondedWithAlternativeMove(State.StateStruct alternativeResponse);
    function alternativeRespondWithMove(
        State.StateStruct memory _alternativeState,
        State.StateStruct memory _nextState,
        bytes[] memory signatures
    )
    public
    onlyWhenCurrentChallengeActive
    {
        // must be valid alternative respond with move according to the framework rules
        require(Rules.validAlternativeRespondWithMove(currentChallenge.state, _alternativeState, _nextState, signatures));

        cancelCurrentChallenge();
        emit RespondedWithAlternativeMove(_nextState);
    }

    event ChallengeCreated(
        address channelId,
        State.StateStruct state,
        uint32 expirationTime,
        address winner
    );

    function createChallenge(uint32 expirationTime, State.StateStruct memory _state, address challengeIssuer) private {
        currentChallenge.channelId = fundedChannelId;
        currentChallenge.state = _state;
        currentChallenge.expirationTime = expirationTime;

        //If game is not over
        if(_state.winner == adress(0)) {
            currentChallenge.winner = challengeIssuer;
        } else {
            currentChallenge.winner = _state.winner;
        }

        emit ChallengeCreated(
            currentChallenge.channelId,
            currentChallenge.state,
            currentChallenge.expirationTime,
            currentChallenge.winner
        );
    }

    function recoverParticipant(address participant, address destination, bytes memory signature)
    internal view returns (address) {
        bytes32 h = keccak256(abi.encodePacked(participant, destination, fundedChannelId));
        return recover(h, signature);
    }

    function withdraw() public onlyWhenGameTerminated {
        (currentChallenge.winner).transfer(address(this).balance);
    }

    function validTransition(State.StateStruct memory _fromState, State.StateStruct memory _toState) public pure returns(bool) {
        return Rules.validTransition(_fromState, _toState);
    }

    function cancelCurrentChallenge() private{
        // TODO: zero out everything(?)
        currentChallenge.expirationTime = 0;
    }

    function currentChallengePresent() public view returns (bool) {
        return currentChallenge.expirationTime > 0;
    }

    function activeChallengePresent() public view returns (bool) {
        return (currentChallenge.expirationTime > now);
    }

    function expiredChallengePresent() public view returns (bool) {
        return currentChallengePresent() && !activeChallengePresent();
    }

    // Modifiers
    modifier onlyWhenCurrentChallengePresent() {
        require(
            currentChallengePresent(),
            "current challenge must be present"
        );
        _;
    }

    modifier onlyWhenCurrentChallengeNotPresent() {
        require(
            !currentChallengePresent(),
            "current challenge must not be present"
        );
        _;
    }

    modifier onlyWhenGameTerminated() {
        require(
            expiredChallengePresent(),
            "game must be terminated"
        );
        _;
    }

    modifier onlyWhenGameOngoing() {
        require(
            !expiredChallengePresent(),
            "game must be ongoing"
        );
        _;
    }

    modifier onlyWhenCurrentChallengeActive() {
        require(
            activeChallengePresent(),
            "active challenge must be present"
        );
        _;
    }
}