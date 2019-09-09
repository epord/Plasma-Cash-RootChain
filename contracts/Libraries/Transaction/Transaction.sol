// Copyright Loom Network 2018 - All rights reserved, Dual licensed on GPLV3
// Learn more about Loom DappChains at https://loomx.io
// All derivitive works of this code must incluse this copyright header on every file

pragma solidity ^0.5.2;

import "./RLPReader.sol";


library Transaction {

    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;

    struct TX {
        uint64 slot;
        address receiver;
        bytes32 hash;
        uint256 prevBlock;
    }

    struct AtomicSwapTX {
        uint64 slot;
        uint256 prevBlock;
        address prevOwner;
        address receiver;
        uint256 secret;
        bytes signature;
        bytes32 secretHash;
        bytes32 hash;
        uint64 swappingSlot;
    }

    function toRLPItems(bytes memory txBytes) internal pure returns (RLPReader.RLPItem[] memory) {
        return txBytes.toRlpItem().toList();
    }

    function isBasicTransaction(RLPReader.RLPItem[] memory rlpTx) internal pure returns (bool) {
        return rlpTx.length == 3;
    }

    function isAtomicSwap(RLPReader.RLPItem[] memory rlpTx) internal pure returns (bool) {
        return rlpTx.length == 9;
    }

    function getBasicTx(RLPReader.RLPItem[] memory rlpTx, bytes memory txBytes) internal pure returns (TX memory) {
        require(isBasicTransaction(rlpTx), "Transaction bytes do not correspond to basic transaction");

        TX memory transaction;

        transaction.slot = uint64(rlpTx[0].toUint());
        transaction.prevBlock = rlpTx[1].toUint();
        transaction.receiver = rlpTx[2].toAddress();
        if (transaction.prevBlock == 0) { // deposit transaction
            transaction.hash = keccak256(abi.encodePacked(transaction.slot));
        } else {
            transaction.hash = keccak256(txBytes);
        }
        return transaction;
    }

    function getAtomicSwapTxs(RLPReader.RLPItem[] memory rlpTx) internal pure returns (AtomicSwapTX[] memory) {
        require(isAtomicSwap(rlpTx), "Transaction bytes do not correspond to an atomic swap transaction");
        AtomicSwapTX[] memory transactions = new AtomicSwapTX[](2);

        transactions[0].slot            = uint64(rlpTx[0].toUint());
        transactions[0].prevBlock       = rlpTx[1].toUint();
        transactions[0].secret          = rlpTx[2].toUint();
        transactions[0].receiver        = rlpTx[3].toAddress();
        transactions[0].swappingSlot    = uint64(rlpTx[4].toUint());

        transactions[1].prevBlock       = uint64(rlpTx[5].toUint());
        transactions[1].secret          = rlpTx[6].toUint();
        transactions[1].receiver        = rlpTx[7].toAddress();
        transactions[1].signature       = rlpTx[8].toBytes();

        transactions[0].prevOwner       = transactions[1].receiver;
        transactions[0].secretHash      = keccak256(abi.encodePacked(transactions[0].secret));
        transactions[0].hash            = atomicSwapHash(transactions[0]);

        transactions[1].slot            = transactions[0].swappingSlot;
        transactions[1].swappingSlot    = transactions[0].slot;
        transactions[1].prevOwner       = transactions[0].receiver;
        transactions[1].hash            = atomicSwapHash(transactions[1]);

        return transactions;
    }

    function atomicSwapHash(AtomicSwapTX memory atx) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(atx.slot, atx.prevBlock, atx.prevOwner, atx.swappingSlot, atx.receiver, atx.secretHash));
    }

    function toBasicTx(AtomicSwapTX memory atx) internal pure returns (TX memory) {
        TX memory transaction;
        transaction.slot        = atx.slot;
        transaction.receiver    = atx.receiver;
        transaction.hash        = atx.hash;
        transaction.prevBlock   = atx.prevBlock;

        return transaction;
    }

    function getHash(bytes memory txBytes) internal pure returns (bytes32 hash) {
        RLPReader.RLPItem[] memory rlpTx = txBytes.toRlpItem().toList();
        uint64 slot = uint64(rlpTx[0].toUint());
        uint256 prevBlock = uint256(rlpTx[1].toUint());

        if (prevBlock == 0) { // deposit transaction
            hash = keccak256(abi.encodePacked(slot));
        } else {
            hash = keccak256(txBytes);
        }
    }

    function getOwner(bytes memory txBytes) internal pure returns (address owner) {
        RLPReader.RLPItem[] memory rlpTx = txBytes.toRlpItem().toList();
        if(isBasicTransaction(rlpTx)) {
            owner = rlpTx[2].toAddress();
        } else if(isAtomicSwap(rlpTx)) {
            owner = rlpTx[3].toAddress();
        } else {
            revert("Could not determine transaction type to retrieve the owner");
        }
    }

}
