
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