// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library MerkleVerifier{
    error InvalidProof();

    /**
     * Computes the Merkle root from a leaf and its Merkle path.
     * @param leaf The leaf node to start the computation from.
     * @param merklePath The array of sibling hashes on the path from the leaf to the root.
     */
    function _computedRoot(
        bytes32 leaf,
        bytes32[] memory merklePath
    )external pure returns(bytes32){
        bytes32 computedHash = leaf;
        for(uint256 i =0;i<merklePath.length;i++){
            bytes32 proofElement = merklePath[i];
            computedHash = _hashPair(computedHash,proofElement);
        }
        return computedHash;
    }
    /**
     * Returns the hash of two bytes32 values in sorted order.
     * @param a The first bytes32 value.
     * @param b The second bytes32 value.
     */
    function _hashPair(
        bytes32 a,
        bytes32 b
    )private pure returns(bytes32){
        return a < b ? _efficientHash(a,b):_efficientHash(b,a);
    }
    /**
     * Efficiently hashes two bytes32 values.
     * @param a The first bytes32 value to hash.
     * @param b The second bytes32 value to hash.
     */
    function _efficientHash(
        bytes32 a,
        bytes32 b
    )private pure returns(bytes32 value){
        assembly{
            mstore(0x00,a)
            mstore(0x20,b)
            value := keccak256(0x00,0x40)
        }
    }
}