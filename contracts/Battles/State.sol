pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

library State {
    enum StateType { PreFundSetup, PostFundSetup, Game, Conclude }

    struct StateStruct {
        address channelType;        //Game address
//        uint256 channelNonce;     //TODO if channel is opened outside Ethereum, revisit this
        address[] participants;

        uint8 stateType;
        uint256 turnNum;

        address winner;  //0 until one is defined
        bytes gameAttributes;       //Current Game State
    }

    function isPreFundSetup(StateStruct memory self) public pure returns (bool) {
        return self.stateType == uint(StateType.PreFundSetup);
    }

    function isPostFundSetup(StateStruct memory self) public pure returns (bool) {
        return self.stateType == uint(StateType.PostFundSetup);
    }

    function isGame(StateStruct memory self) public pure returns (bool) {
        return self.stateType == uint(StateType.Game);
    }

    function isConclude(StateStruct memory self) public pure returns (bool) {
        return self.stateType == uint(StateType.Conclude);
    }

    //TODO remove this if ChannelNonce can be avoided
    function channelId(StateStruct memory _state) public pure returns (address) {
        bytes32 h = keccak256(
            abi.encodePacked(_state.channelType, _state.channelNonce, _state.participants)
        );
        address addr;
        assembly {
            mstore(0, h)
            addr := mload(0)
        }
        return addr;
    }

    function mover(StateStruct memory _state) public pure returns (address) {
        return _state.participants[_state.turnNum % 2];
    }

    //State is signed by mover
    function requireSignature(StateStruct memory _state, bytes calldata signature) public pure {
        require(
            ecverify(abi.encode(_state), mover(_state), signature),
            "mover must have signed state"
        );
    }

    function requireFullySigned(StateStruct memory _state, uint8[] memory _v, bytes32[] memory _r, bytes32[] memory _s) public pure {
        for(uint i = 0; i < _state.numberOfParticipants; i++) {
            require(
                _state.participants[i] == recoverSigner(abi.encode(_state), _v[i], _r[i], _s[i]),
                "all movers must have signed state"
            );
        }
    }

    function gameAttributesEqual(StateStruct memory _state, StateStruct memory _otherState) public pure returns (bool) {
        return keccak256(_state.gameAttributes) == keccak256(_otherState.gameAttributes);
    }

    function winnerEqual(StateStruct memory _state, StateStruct memory _otherState) public pure returns (bool) {
        return keccak256(abi.encodePacked(_state.winner)) == keccak256(abi.encodePacked(_otherState.winner));
    }
}