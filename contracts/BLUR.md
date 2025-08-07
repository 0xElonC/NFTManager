# BLUR 交易所学习笔记
blur 这是一个建立在ETH上的非同质化代币（NFT）去中心化交易平台
### 特色功能
1、创新竞拍机制
2、高效的交易费用
3、聚合交易功能

### 数据结构
```
// 交易方向
enum Side { Buy, Sell }
// 签名类型
enum SignatureVersion { Single, Bulk }
// 资产类型
enum AssetType { ERC721, ERC1155 }

// 收费详情
struct Fee {
    uint16 rate; // 比率
    address payable recipient; // 接收者
}

// 订单数据
struct Order {
    address trader; // 订单创建者
    Side side; // 交易方向
    address matchingPolicy; // 交易策略
    address collection; // 合约地址
    uint256 tokenId; // tokenId
    uint256 amount; // 数量
    address paymentToken; // 支付的代币
    uint256 price; // 价格
    uint256 listingTime; // 挂单时间
    /* Order expiration timestamp - 0 for oracle cancellations. */
    uint256 expirationTime; // 过期时间，oracle cancellations 的是 0
    Fee[] fees; // 费用
    uint256 salt;
    bytes extraParams; // 额外数据，如果长度大于 0，且第一个元素是 1 则表示是oracle authorization
}

// 订单和签名数据
struct Input {
    Order order; // 订单数据
    uint8 v; 
    bytes32 r;
    bytes32 s;
    bytes extraSignature; // 批量订单校验和 Oracle 校验使用的额外数据
    SignatureVersion signatureVersion; // 签名类型
    uint256 blockNumber; // 挂单时的区块高度
}

// 交易双方的数据
struct Execution {
  Input sell;
  Input buy;
}

```

### 订单执行流程
（BlurExchange.sol）
1、参数校验，确认卖单方向
2、计算订单哈希（买卖双方）、
3、验证订单参数
4、验证双方签名
5、验证订单是否匹配（ERC721 / ERC1155）
6、标记订单完成
7、转移NFT，再转移资金
8、发出事件

### 订单策略

1、标准ERC721
2  安全收藏BID策略 ：用于集合出价，买家可以购买集合中的任何一个NFT

### 签名验证

Blur两种验证机制
1、单一签名：用户对单个订单进行签名 
2、批量签名：通过merkle树，用户一次可以签名多个订单，将所有要签名的订单哈希通过merkle树聚合成一个根哈希，然后对根哈希进行签字
```

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

//简化的订单结构
struct Order{
    address trader;
    address nftContract;
    uint256 tokenId;
    uint256 price;
    uint256 deadline;
    bool isSellOrder;
}

//签名枚举类型
enum SignatureVersion{
    single,
    bluk
}

contract BulkSignatureDemo{
    
    /**
     * @dev 计算订单的哈希值
     * @param order 订单结构体
     * @return 订单的哈希值
     */
    function _getOrderHash(Order memory order) internal pure returns(bytes32){
        return keccak256(abi.encode(
            order.trader, 
            order.nftContract,
            order.tokenId,
            order.price,
            order.deadline,
            order.isSellOrder
        ));
    }

    function _hashToSign(bytes32 dataHash) internal pure returns(bytes32){
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));
    }

    function _mergeHashes(bytes32 a,bytes32 b)internal pure returns(bytes32){
        return a<b?keccak256(abi.encodePacked(a,b)):keccak256(abi.encodePacked(b,a));
    } 

    function buildMerkleTree(Order[] memory orders) public pure returns(bytes32 root){
        require(orders.length>0,"order is empty");

        //计算所有叶子节点哈希
        bytes32[] memory leaves = new bytes32[](orders.length+1);
        for(uint i=0;i<orders.length;i++){
            leaves[i] = _getOrderHash(orders[i]);
        }
        return _buildMerkleTree(leaves);
    }

    function _buildMerkleTree(bytes32[] memory leaves) internal pure returns(bytes32){
        if(leaves.length == 1){
            return leaves[0];
        }

        bytes32[] memory newLeaves = new bytes32[]((leaves.length+1)/2);
         for (uint i = 0; i < newLeaves.length; i++) {
            uint j = i * 2;
            if (j + 1 < leaves.length) {
                newLeaves[i] = _mergeHashes(leaves[j], leaves[j + 1]);
            } else {
                newLeaves[i] = leaves[j];
            }
        }
        
        return _buildMerkleTree(newLeaves);
    }

    function getMerklePath(Order[] memory orders, uint256 index) public pure returns (bytes32[] memory path) {
        require(index < orders.length, "Index out of bounds");
        
        // 计算所有叶子节点哈希
        bytes32[] memory leaves = new bytes32[](orders.length);
        for (uint i = 0; i < orders.length; i++) {
            leaves[i] = _getOrderHash(orders[i]);
        }
        
        return _getMerklePath(leaves, index);
    }

     /**
     * @dev 从哈希数组计算Merkle路径
     */
    function _getMerklePath(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        if (leaves.length == 1) {
            return new bytes32[](0);
        }
        
        bytes32[] memory path;
        uint256 pathIndex = 0;
        bytes32[] memory currentLeaves = leaves;
        
        while (currentLeaves.length > 1) {
            uint256 newLength = (currentLeaves.length + 1) / 2;
            bytes32[] memory newLeaves = new bytes32[](newLength);
            
            for (uint i = 0; i < currentLeaves.length; i += 2) {
                uint j = i / 2;
                if (i + 1 < currentLeaves.length) {
                    newLeaves[j] = _mergeHashes(currentLeaves[i], currentLeaves[i + 1]);
                    
                    // 记录路径
                    if (i == index || i + 1 == index) {
                        path = path.length == 0 ? new bytes32[](1) : new bytes32[](path.length + 1);
                        path[pathIndex] = i == index ? currentLeaves[i + 1] : currentLeaves[i];
                        pathIndex++;
                    }
                } else {
                    newLeaves[j] = currentLeaves[i];
                    
                    // 记录路径
                    if (i == index) {
                        path = path.length == 0 ? new bytes32[](1) : new bytes32[](path.length + 1);
                        path[pathIndex] = currentLeaves[i];
                        pathIndex++;
                    }
                }
            }
            
            index = index / 2;
            currentLeaves = newLeaves;
        }
        
        return path;
    }

    function _verifySignature(
        address signer,
        bytes32 hashTosign,
        uint8 v,
        bytes32 r,
        bytes32 s
    )internal pure returns(bool){
        address recoverdSigner = ecrecover(hashTosign,v,r,s);
        return recoverdSigner!= address(0) && recoverdSigner == signer;
    }

    function verifyOrder(
        Order memory order,
        SignatureVersion version,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes calldata extraData
    ) external view returns(bool){
        require(block.timestamp>order.deadline,"Order expired");

        bytes32 hashToSign;

        if(version == SignatureVersion.single){
            bytes32 orderHash = _getOrderHash(order);
            hashToSign = _hashToSign(orderHash);
        }else{
            bytes32 orderHash = _getOrderHash(order);

            bytes32[] memory merklePath = abi.decode(extraData, (bytes32[]));
             // 计算根哈希
            bytes32 currentHash = orderHash;
            for (uint i = 0; i < merklePath.length; i++) {
                currentHash = _mergeHashes(currentHash, merklePath[i]);
            }
            hashToSign = _hashToSign(currentHash);
        }

        return _verifySignature(order.trader,hashToSign,v,r,s);
    }



    //辅助测试函数
    function createTestOrder(
        address trader,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        bool isSellOrder
    ) public pure returns(Order memory){
         return Order({
            trader: trader,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            deadline: deadline,
            isSellOrder: isSellOrder
        });
    }

    //生成测试用例
      /**
     * @dev 生成测试用的订单数组
     */
    function createTestOrders(address trader, address nftContract) external view returns (Order[] memory) {
        Order[] memory orders = new Order[](3);
        uint256 deadline = block.timestamp + 86400; // 24小时后过期
        
        orders[0] = createTestOrder(trader, nftContract, 1, 1 ether, deadline, true);
        orders[1] = createTestOrder(trader, nftContract, 2, 2 ether, deadline, true);
        orders[2] = createTestOrder(trader, nftContract, 3, 3 ether, deadline, true);
        
        return orders;
    }
}
```


注：还有一个oracle1授权机制，用于链下取消订单

### 订单取消机制
1、单个取消:调用 cancelOrdel 将订单标记为取消
2、批次取消
3、增加nonce：增加用户NONCE使用户所有先前的订单无效

### 资产和资金转移
1、资金转移：支持ETH和WETH支付，通过_transferTo和_transferFees函数处理
2、NFT转移：通过ExecutionDelegate代理合约处理NFT的转移，支持ERC721和ERC1155
3、blur pool： 类似WETH的ETH池，只能由BlurExchange和BlurSwap调用转账

