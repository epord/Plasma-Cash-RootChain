pragma solidity ^0.5.12;
pragma experimental ABIEncoderV2;

import "../../RootChain.sol";
import "../Transaction/Transaction.sol";
import "../ECVerify.sol";
import "../Plasma/ChallengeLib.sol";


library PlasmaChallenges {

    using Transaction for bytes;
    using ECVerify for bytes32;


    /**
     * @dev Checks a transaction to be a direct spend from an Exit
     * @param exit        RootChain.Exit exit to be challenged
     * @param txBytes     RLP encoded bytes of the transaction to make a Challenge After. Should be a direct spend.
     *                     Has to be the same slot, signed by the same owner and its' prevBlock equal to exit's exitBlock
     * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
     * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof. Must be greater to
     *                    exit.exitBlock.
     */
     function checkAfter(
        RootChain.Exit memory exit,
        RootChain rootChain,
        bytes memory txBytes,
        bytes memory proof,
        bytes memory signature,
        uint blockNumber
    ) internal view {

        require(exit.exitBlock < blockNumber);
        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.hash.ecverify(signature, exit.owner));
        require(txData.slot == exit.slot);
        require(txData.prevBlock == exit.exitBlock);
    }


    /**
     * @dev Checks a transaction to be a previous double spend from an Exit
     * @param exit        RootChain.Exit exit to be challenged
     * @param txBytes     RLP encoded bytes of the transaction to make a Challenge Between. Should be a direct spend of
     *                    the exit.prevBlock. Has to be the same slot, signed by the same owner and the blockNumber
     *                    Should be before exit.exitBlock.
     * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
     * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof. Must be between exit.prevBlock
     *                    and exit.exitBlock.
     */
    function checkBetween(
        RootChain.Exit memory exit,
        RootChain rootChain,
        bytes memory txBytes,
        bytes memory proof,
        bytes memory signature,
        uint blockNumber
    ) internal view {

        require(exit.exitBlock > blockNumber && exit.prevBlock < blockNumber);

        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.hash.ecverify(signature, exit.prevOwner));
        require(txData.slot == exit.slot);
    }

    /**
     * @dev Checks a transaction against an exit for a Challenge Before
     * @param exit        RootChain.Exit exit to be challenged
     * @param txBytes     RLP encoded bytes of the transaction to make a Challenge Before.
     * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
     * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof. Must be previous to
     *                    exit.prevBlock.
     */
    function checkBefore(
        RootChain.Exit memory exit,
        RootChain rootChain,
        bytes memory txBytes,
        bytes memory proof,
        uint blockNumber
    ) internal view {
        require(blockNumber <= exit.prevBlock);
        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.slot == exit.slot);
    }

    /**
    * @dev Checks a Plasma Challenge's response against an exit.
    * @param exit        RootChain.Exit exit to be challenged
    * @param challenge   ChallengeLib.Challenge challenge to respond to
    * @param blockNumber BlockNumber of the transaction to be checked for the inclusion proof. Should be a future spend of
    *                    the challenge.challengingBlockNumber but before the exit.exitBlock. Has to be the same slot,
    *                    signed by the same owner.
    * @param txBytes     RLP encoded bytes of the transaction to proof the spending of the challenge. Must
    * @param proof       Bytes needed for the proof of inclusion of txBytes in the Plasma block
    * @param signature   Signature of the txBytes to prove its validity. Must be signed by the challenged owner
    */
    function checkResponse(
        RootChain.Exit memory exit,
        RootChain rootChain,
        ChallengeLib.Challenge memory challenge,
        uint256 blockNumber,
        bytes memory txBytes,
        bytes memory signature,
        bytes memory proof
    ) internal view {

        rootChain.checkTX(txBytes, proof, blockNumber);
        Transaction.TX memory txData = txBytes.getTransaction();
        require(txData.hash.ecverify(signature, challenge.owner));
        require(txData.slot == exit.slot);
        require(blockNumber > challenge.challengingBlockNumber);
        require(blockNumber <= exit.exitBlock);
    }


}

