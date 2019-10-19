pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

contract TestContract {
    address[] ad;

    struct State {
        uint256 channelId;
        address payable channelType;        //Game address
        address[] participants;
        uint256 turnNum;
        bytes gameAttributes;       //Current Game State
    }

    //State is signed by mover
    function requireSignature(bytes memory a) public returns(bytes memory) {
        ad.push(msg.sender);
        ad.push(msg.sender);
        State memory state = State(1, msg.sender, ad, 1, a);
        bytes memory answer = abi.encodePacked(state.channelId, state.channelType, state.participants, state.turnNum, state.gameAttributes);
        return answer;
    }

}