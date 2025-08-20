// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/NftToken_Management/NFTOrderManager.sol";
import "../contracts/TestERC721.sol";
import "../contracts/NftToken_Management/struct/OrderStruct.sol";
import "../contracts/NftToken_Management/utils/EIP712.sol";
import "../contracts/NftToken_Management/ExecutionDelegate.sol";
import "../contracts/NftToken_Management/policyManage/PolicyManager.sol";
import "../contracts/NftToken_Management/policyManage/interfaces/IMatchingPolicy.sol";
import "../contracts/NftToken_Management/policyManage/matchingPolices/StandardPolicyERC721.sol";

contract NFTOrderManagerBulkTest is Test, EIP712{
    // 核心合约
    NFTOrderManager public nftOrderManager;
    ExecutionDelegate public executionDelegate;
    PolicyManager public policyManager;
    TestERC721 public nft;
    StandardPolicyERC721 public standardPolicyERC721;

    // 测试账户
    uint256 public sellerPK1 = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public sellerPK2 = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 public sellerPK3 = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 public buyerPK1 = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    address public seller1;
    address public seller2;
    address public seller3;
    address public buyer1;
    address public owner;

    // 常量
    uint256 public constant TOKEN_ID1 = 1;
    uint256 public constant TOKEN_ID2 = 2;
    uint256 public constant TOKEN_ID3 = 3;
    uint256 public constant PRICE1 = 100000000000000000 wei;
    uint256 public constant PRICE2 = 200000000000000000 wei;
    uint256 public constant PRICE3 = 300000000000000000 wei;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public{
        seller1 = vm.addr(sellerPK1);
        seller2 = vm.addr(sellerPK2);
        seller3 = vm.addr(sellerPK3);
        buyer1 = vm.addr(buyerPK1);
        owner = address(this);
        //部署依赖合约
        standardPolicyERC721 = new StandardPolicyERC721();
        address[] memory whiteList = new address[](1);
        whiteList[0] = address(standardPolicyERC721);
        policyManager = new PolicyManager(owner,whiteList);
        executionDelegate = new ExecutionDelegate(owner);
        vm.prank(owner);
        nft = new TestERC721("XYD","XYD",owner);

        //初始化OrderManage
        nftOrderManager = new NFTOrderManager();
        nftOrderManager.initialize(
            address(this),
            IPolicyManager(address(policyManager)),
            IExecutionDelegate(address(executionDelegate))
        );

        nft.mint(seller1);
        nft.mint(seller2);
        nft.mint(seller3);
        //授权执行代理转移
        vm.prank(seller1);
        nft.approveALL(address(executionDelegate),true);
        vm.prank(seller2);
        nft.approveALL(address(executionDelegate),true);
        vm.prank(seller3);
        nft.approveALL(address(executionDelegate),true);

        console.log(nft.isApprovedForAll(seller2, address(executionDelegate)));
        assertEq(nft.isApprovedForAll(seller1, address(executionDelegate)), true);
        assertEq(nft.isApprovedForAll(seller2, address(executionDelegate)), true);
        assertEq(nft.isApprovedForAll(seller3, address(executionDelegate)), true);

        
        executionDelegate.approveContract(address(nftOrderManager));
    }

    /**
     * 测试批量执行两个订单
     */
    function testBulkExecuteSuccess() public {
         // 1. 卖家1创建卖单（TOKEN_ID1，0.1 ETH）
        Order memory sell1 = createSellOrder(
            seller1,
            address(nft),
            TOKEN_ID1,
            AssetType.ERC721,
            PRICE1,
            1
        );
        Input memory sellInput1 = signOrder(sellerPK1,sell1, SignatureVersion.Single);
         // 2. 卖家2创建卖单（TOKEN_ID2，0.2 ETH）
        Order memory sell2 = createSellOrder(
            seller2,
            address(nft),
            TOKEN_ID2,
            AssetType.ERC721,
            PRICE2,
            1
        );
        Input memory sellInput2 = signOrder(sellerPK2, sell2, SignatureVersion.Single);

        // 3. 卖家3创建卖单（TOKEN_ID3，0.3 ETH）
        Order memory sell3 = createSellOrder(
            seller3,
            address(nft),
            TOKEN_ID3,
            AssetType.ERC721,
            PRICE3,
            1
        );
        Input memory sellInput3 = signOrder(sellerPK3, sell3, SignatureVersion.Single);

        vm.warp(block.timestamp + 10 seconds);

        //买家同时购买多个卖单
        Order memory buy1 = createBuyOrder(
            buyer1, // 同一买家地址
            address(nft),
            TOKEN_ID1,
            AssetType.ERC721,
            PRICE1, // 匹配卖家1价格
            1
        );

        Order memory buy2 = createBuyOrder(
            buyer1, // 同一买家地址
            address(nft),
            TOKEN_ID2,
            AssetType.ERC721,
            PRICE2, // 匹配卖家2价格
            1
        );

        Order memory buy3 = createBuyOrder(
            buyer1, // 同一买家地址
            address(nft),
            TOKEN_ID3,
            AssetType.ERC721,
            PRICE3, // 匹配卖家3价格
            1
        );
        //构建merkle树
        bytes32[] memory buyOrderHashes = new bytes32[](3);
        buyOrderHashes[0] = nftOrderManager._hashOrder(buy1, nftOrderManager.nonces(buyer1) + 0); // nonce按顺序递增
        buyOrderHashes[1] = nftOrderManager._hashOrder(buy2, nftOrderManager.nonces(buyer1) + 1);
        buyOrderHashes[2] = nftOrderManager._hashOrder(buy3, nftOrderManager.nonces(buyer1) + 2);

        (bytes32 merkleRoot, bytes32[][] memory merklePaths) = buildMerkleTree(buyOrderHashes);

        //买家对merkle根签名
        bytes32 rootHashToSign = nftOrderManager._hashToSignRoot(merkleRoot);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPK1, rootHashToSign);
        //构造买家买单的Input（使用Bulk签名版本+Merkle路径）
        Input memory buyInput1 = Input({
            order: buy1,
            v: v,
            r: r,
            s: s,
            extraSignature:  abi.encode(merklePaths[0]),
            signatureVersion: SignatureVersion.Bulk,
            blockNumber: block.number
        });

        Input memory buyInput2 = Input({
            order: buy2,
            v: v,
            r: r,
            s: s,
            extraSignature: abi.encode(merklePaths[1]),
            signatureVersion: SignatureVersion.Bulk,
            blockNumber: block.number
        });

        Input memory buyInput3 = Input({
            order: buy3,
            v: v,
            r: r,
            s: s,
            extraSignature: abi.encode(merklePaths[2]),
            signatureVersion: SignatureVersion.Bulk,
            blockNumber: block.number
        });

        Execution[] memory executions = new Execution[](3);
        executions[0] = Execution({sell: sellInput1, buy: buyInput1});
        executions[1] = Execution({sell: sellInput2, buy: buyInput2});
        executions[2] = Execution({sell: sellInput3, buy: buyInput3});
        //给买家充值ETH
        uint256 totalPrice = PRICE1 + PRICE2 + PRICE3;
        vm.deal(buyer1,totalPrice);
        vm.prank(buyer1);
        nftOrderManager.blukExecute{value: totalPrice}(executions);
        // 验证结果
        // 所有订单标记为已完成
        bytes32 sellHash1 = nftOrderManager._hashOrder(sell1, sell1.nonce);
        bytes32 sellHash2 = nftOrderManager._hashOrder(sell2, sell2.nonce);
        bytes32 sellHash3 = nftOrderManager._hashOrder(sell3, sell3.nonce);
        bytes32 buyHash1 = buyOrderHashes[0];
        bytes32 buyHash2 = buyOrderHashes[1];
        bytes32 buyHash3 = buyOrderHashes[2];

        assertEq(MerkleVerifier._computedRoot(buyOrderHashes[0], merklePaths[0]), merkleRoot, unicode"第一个订单路径无效");
        assertEq(MerkleVerifier._computedRoot(buyOrderHashes[1], merklePaths[1]), merkleRoot, unicode"第二个订单路径无效"); // 关键
        assertEq(MerkleVerifier._computedRoot(buyOrderHashes[2], merklePaths[2]), merkleRoot, unicode"第三个订单路径无效"); // 关键
        assertEq(nftOrderManager.cancelOrFilled(sellHash1), true);
        assertEq(nftOrderManager.cancelOrFilled(sellHash2), true);
        assertEq(nftOrderManager.cancelOrFilled(sellHash3), true);
        assertEq(nftOrderManager.cancelOrFilled(buyHash1), true);
        assertEq(nftOrderManager.cancelOrFilled(buyHash2), true);
        console.logBytes32(buyHash2);
        assertEq(nftOrderManager.cancelOrFilled(buyHash3), true);

        // 买家收到NFT，卖家收到款项
        assertEq(nft.ownerOf(TOKEN_ID1), buyer1);
        assertEq(nft.ownerOf(TOKEN_ID2), buyer1);
        assertEq(nft.ownerOf(TOKEN_ID3), buyer1);
        assertEq(seller1.balance, PRICE1);
        assertEq(seller2.balance, PRICE2);
        assertEq(seller3.balance, PRICE3);
        assertEq(buyer1.balance, 0);

    }

    /**
     * 工具函数
     */
    function createSellOrder(
        address trader,
        address nftContract,
        uint256 tokenId,
        AssetType assetType,
        uint256 price,
        uint256 quantity
    ) internal view returns(Order memory){
        return Order({
            trader: trader,
            side: Side.Sell,
            nftContract: nftContract,
            tokenId: tokenId,
            AssetType: assetType,
            price: price,
            amount: quantity,
            validUntil: block.timestamp + 1 hours,
            createAT: block.timestamp,
            paymentToken: address(0), // 使用 ETH 支付
            matchingPolicy: address(standardPolicyERC721),
            fees: new Fee[](0), // 无额外费用
            extraParams: "",
            nonce: nftOrderManager.nonces(trader)
        });
    }


    function createBuyOrder(
        address trader,
        address nftContract,
        uint256 tokenId,
        AssetType assetType,
        uint256 price,
        uint256 quantity
    ) internal view returns (Order memory) {
        return Order({
            trader: trader,
            side: Side.Buy,
            nftContract: nftContract,
            tokenId: tokenId,
            AssetType: assetType,
            price: price,
            amount: quantity,
            validUntil: block.timestamp + 1 hours,
            createAT: block.timestamp,
            paymentToken: address(0), // 使用 ETH 支付
            matchingPolicy: address(standardPolicyERC721),
            fees: new Fee[](0), // 无额外费用
            extraParams: "",
            nonce: nftOrderManager.nonces(trader)
        });
    }

    function buildMerkleTree(bytes32[] memory leaves)
    internal
    pure 
    returns(bytes32 root, bytes32[][] memory paths){
         uint256 leafCount = leaves.length;
        paths = new bytes32[][](leafCount); 
        for (uint256 i = 0; i < leafCount; i++) {
            paths[i] = new bytes32[](0);
        }

        bytes32[] memory current = leaves;
        while (current.length > 1) {
            uint256 nextLength = (current.length + 1) / 2;
            bytes32[] memory next = new bytes32[](nextLength);

            for (uint256 i = 0; i < current.length; i += 2) {
                uint256 j = i / 2;
                bytes32 left = current[i];
                bytes32 right = (i + 1 < current.length) ? current[i + 1] : left;

                // 1. 排序节点（小在前，大在后）
                bool leftIsSmaller = left < right;
                bytes32 sortedFirst = leftIsSmaller ? left : right;
                bytes32 sortedSecond = leftIsSmaller ? right : left;
                next[j] = keccak256(abi.encodePacked(sortedFirst, sortedSecond));

                // 2. 记录路径：根据排序结果，明确当前节点在排序后扮演的角色
                // 处理左叶子节点（i）
                if (i < leafCount) {
                    // 左节点在排序后可能是sortedFirst或sortedSecond
                    bytes32 sibling = leftIsSmaller ? sortedSecond : sortedFirst;
                    paths[i] = push(paths[i], sibling);
                }
                // 处理右叶子节点（i+1）
                if (i + 1 < current.length && i + 1 < leafCount) {
                    // 右节点在排序后可能是sortedFirst或sortedSecond
                    bytes32 sibling = leftIsSmaller ? sortedFirst : sortedSecond;
                    paths[i + 1] = push(paths[i + 1], sibling);
                }
            }

            current = next;
        }

        root = current.length > 0 ? current[0] : bytes32(0);
    }

    function signOrder(uint256 privateKey, Order memory order,SignatureVersion signtureVersion)internal view returns(Input memory){
        bytes32 orderHash = nftOrderManager._hashOrder(order,order.nonce);
        bytes32 domain = nftOrderManager.getDOMAIN_SEPARATOR();
        bytes32 hashToSign = keccak256(abi.encodePacked("\x19\x01",domain,orderHash));
        
        (uint8 v,bytes32 r,bytes32 s) = vm.sign(privateKey,hashToSign);
        return Input({
            order: order,
            v:v,
            r:r,
            s:s,
            extraSignature: "",
            signatureVersion: signtureVersion,
            blockNumber: block.number
        });
    }

     // 辅助函数：向数组添加元素
    function push(bytes32[] memory arr, bytes32 value) internal pure returns (bytes32[] memory) {
        bytes32[] memory newArr = new bytes32[](arr.length + 1);
        for (uint256 i = 0; i < arr.length; i++) {
            newArr[i] = arr[i];
        }
        newArr[arr.length] = value;
        return newArr;
    }
}