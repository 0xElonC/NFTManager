// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Order,Fee} from "../struct/OrderStruct.sol";

import "hardhat/console.sol";
contract EIP712{

    struct EIP712Domain{
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    bytes32 constant public ORDER_TYPEHASH = keccak256(
       "Order(address trader,uint8 side,address matchingPolicy,address nftContract,uint256 tokenId,uint8 AssetType,uint256 amount,address paymentToken,uint256 price,uint256 validUntil,uint256 createAT,Fee[] fees,bytes extraParams,uint256 nonce)Fee(uint16 rate,address recipient)"
    );

    bytes32 constant public EIP712DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 constant public FEE_TYPEHASH = keccak256(
        "Fee(uint16 rate,address recipient)"
    );

    bytes32 constant public ROOT_TYPEHASH = keccak256(
        "Root(bytes32 root)"
    );

    bytes32 public DOMAIN_SEPARATOR;


    function _hashDomain(EIP712Domain memory eip712Domain)
        internal
        pure
        returns(bytes32){
            return keccak256(
                abi.encode(
                    EIP712DOMAIN_TYPEHASH,
                    keccak256(bytes(eip712Domain.name)),
                    keccak256(bytes(eip712Domain.version)),
                    eip712Domain.chainId,
                    eip712Domain.verifyingContract
                )
            );
        }

    /**
     * Hashes an order with the provided nonce for EIP712 signature.
     * @param order The order struct containing trade details.
     * @param nonce The unique nonce for the order.
     */
    function _hashOrder(Order calldata order,uint256 nonce)
        internal
        pure
        returns(bytes32){
            return keccak256(
                bytes.concat(
                    abi.encode(
                        ORDER_TYPEHASH,
                        order.trader,
                        order.side,
                        order.matchingPolicy,
                        order.nftContract,
                        order.tokenId,
                        order.AssetType,
                        order.amount,
                        order.paymentToken,
                        order.price,
                        order.validUntil,
                        order.createAT,
                        _packedFee(order.fees),
                        keccak256(order.extraParams),
                        nonce
                    )
                )
            );
        }

    function _hashToSign(bytes32 orderHash)
        internal
        view
        returns(bytes32 hash){
            return keccak256(abi.encodePacked(
                 "\x19\x01",
                DOMAIN_SEPARATOR,
                orderHash
            ));
        }

    function _hashToSignRoot(bytes32 root)
        internal
        view
        returns(bytes32 hash){
            return keccak256(abi.encodePacked(
                  "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encodePacked(
                    ROOT_TYPEHASH,
                    root
                ))
            ));
        }

    function _packedFee(Fee[] calldata fees)
        internal
        pure
        returns(bytes32){
            bytes32[] memory hashFees = new bytes32[](fees.length);
            for(uint256 i=0;i<fees.length;i++){
                hashFees[i] = _hashFee(fees[i]);
            }
            return keccak256(abi.encodePacked(hashFees));
        }

    function _hashFee(Fee calldata fee)
        internal
        pure
        returns(bytes32){
            return keccak256(
                abi.encode(
                    FEE_TYPEHASH,
                    fee.rate,
                    fee.recipient
                )
            );
        }
}