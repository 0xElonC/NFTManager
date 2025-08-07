// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

    enum AssetType {
        ERC721,
        ERC1155
    }
    enum SignatureVersion {Single,Bulk}
    enum Side{Sell,Buy}

    struct Order {
        address trader;
        Side side;
        address matchingPolicy;
        address nftContract;
        uint256 tokenId;
        AssetType AssetType;
        uint256 amount;
        address paymentToken;
        uint256 price; //wei
        uint256 validUntil;
        uint256 createAT;
        Fee[] fees;
        bytes extraParams; // 额外数据，如果长度大于 0，且第一个元素是 1 则表示是oracle authorization
    }

    struct Input{
        Order order;
        uint8 v;
        bytes32 r;
        bytes32 s;
        bytes extraSignature; // 批量订单校验时保存默克尔树路径上的所有节点， 当order.order.expirationTime == 0即Oracle 校验时保存默克尔树路径上的所有节点以及Oracle的签名vrs，oracle的签名一律是单签，也就是签一个订单的hash
        SignatureVersion signatureVersion;
        uint256 blockNumber;
    }

    struct Fee {
        uint16 rate;
        address payable recipient;
}

    