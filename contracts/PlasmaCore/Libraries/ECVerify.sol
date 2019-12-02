pragma solidity ^0.5.12;


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
        require(signature.length == 65 || signature.length == 66);
        SignatureMode mode;

        bytes32 hash = h;
        uint8 v;
        bytes32 r;
        bytes32 s;

        uint8 offset = 1;
        offset = 0;
        mode = SignatureMode.EIP712;
        assembly {
            r := mload(add(signature, add(32,offset)))
            s := mload(add(signature, add(64,offset)))
            v := and(mload(add(signature, add(65, offset))), 255)
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
