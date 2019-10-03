pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

import 'openzeppelin-solidity/contracts/token/ERC721/ERC721.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';
import "openzeppelin-solidity/contracts/drafts/Counters.sol";
import "../Libraries/Pokedex.sol";

contract CryptoMons is ERC721, Ownable, Pokedex {

    using Counters for Counters.Counter;

    address plasma;
    mapping (uint256 => Pokemon) cryptomons;

    uint256 constant CRYPTOMON_VALUE = 0.01 ether;
    Counters.Counter tokenCount;

    modifier CMPayment() {
        require(msg.value == CRYPTOMON_VALUE, "Payment must be CryptoMon value");
        _;
    }

    modifier isERC721Receiver(address to) {
        // require(_checkOnERC721Received(address(0), to, 0, ""), "Plasma must be an ERC721Receiver implementer");
        _;
    }

    constructor (address _plasma) public isERC721Receiver(_plasma) {
        plasma = _plasma;
    }

    function changePlasma(address newPlasma) public onlyOwner isERC721Receiver(newPlasma) {
        plasma = newPlasma;
    }

    function buyCryptoMon() external payable CMPayment {
        create();
    }

    function depositToPlasmaWithData(uint tokenId, bytes memory _data) public {
        safeTransferFrom(msg.sender, plasma, tokenId, _data);
    }

    function depositToPlasma(uint tokenId) public {
        safeTransferFrom(msg.sender, plasma, tokenId);
    }

    function create() private {
        tokenCount.increment();
        _mint(msg.sender, tokenCount.current());
        cryptomons[tokenCount.current()] = generateNewPokemon();
    }

    function getCryptomon(uint8 id) public view returns (Pokemon memory) {
        return cryptomons[id];
    }

}
