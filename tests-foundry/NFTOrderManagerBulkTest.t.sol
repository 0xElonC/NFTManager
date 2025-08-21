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

contract NFTOrderManagerBulkTest is Test, EIP712 {
    // 核心合约
    NFTOrderManager public nftOrderManager;
    ExecutionDelegate public executionDelegate;
    PolicyManager public policyManager;
    TestERC721 public nft;
    StandardPolicyERC721 public standardPolicyERC721;

    // 测试账户
    uint256 public sellerPK1 =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public sellerPK2 =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 public sellerPK3 =
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 public buyerPK1 =
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
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

    function setUp() public {
        seller1 = vm.addr(sellerPK1);
        seller2 = vm.addr(sellerPK2);
        seller3 = vm.addr(sellerPK3);
        buyer1 = vm.addr(buyerPK1);
        owner = address(this);
        //部署依赖合约
        standardPolicyERC721 = new StandardPolicyERC721();
        address[] memory whiteList = new address[](1);
        whiteList[0] = address(standardPolicyERC721);
        policyManager = new PolicyManager(owner, whiteList);
        executionDelegate = new ExecutionDelegate(owner);
        vm.prank(owner);
        nft = new TestERC721("XYD", "XYD", owner);

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
        nft.approveALL(address(executionDelegate), true);
        vm.prank(seller2);
        nft.approveALL(address(executionDelegate), true);
        vm.prank(seller3);
        nft.approveALL(address(executionDelegate), true);

        console.log(nft.isApprovedForAll(seller2, address(executionDelegate)));
        assertEq(
            nft.isApprovedForAll(seller1, address(executionDelegate)),
            true
        );
        assertEq(
            nft.isApprovedForAll(seller2, address(executionDelegate)),
            true
        );
        assertEq(
            nft.isApprovedForAll(seller3, address(executionDelegate)),
            true
        );

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
        Input memory sellInput1 = signOrder(
            sellerPK1,
            sell1,
            SignatureVersion.Single
        );
        // 2. 卖家2创建卖单（TOKEN_ID2，0.2 ETH）
        Order memory sell2 = createSellOrder(
            seller2,
            address(nft),
            TOKEN_ID2,
            AssetType.ERC721,
            PRICE2,
            1
        );
        Input memory sellInput2 = signOrder(
            sellerPK2,
            sell2,
            SignatureVersion.Single
        );

        // 3. 卖家3创建卖单（TOKEN_ID3，0.3 ETH）
        Order memory sell3 = createSellOrder(
            seller3,
            address(nft),
            TOKEN_ID3,
            AssetType.ERC721,
            PRICE3,
            1
        );
        Input memory sellInput3 = signOrder(
            sellerPK3,
            sell3,
            SignatureVersion.Single
        );

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
        buyOrderHashes[0] = nftOrderManager._hashOrder(
            buy1,
            nftOrderManager.nonces(buyer1) + 0
        ); // nonce按顺序递增
        buyOrderHashes[1] = nftOrderManager._hashOrder(
            buy2,
            nftOrderManager.nonces(buyer1) + 1
        );
        buyOrderHashes[2] = nftOrderManager._hashOrder(
            buy3,
            nftOrderManager.nonces(buyer1) + 2
        );

        (bytes32 merkleRoot, bytes32[][] memory merklePaths) = buildMerkleTree(
            buyOrderHashes
        );

        //买家对merkle根签名
        bytes32 rootHashToSign = nftOrderManager._hashToSignRoot(merkleRoot);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPK1, rootHashToSign);
        //构造买家买单的Input（使用Bulk签名版本+Merkle路径）
        Input memory buyInput1 = Input({
            order: buy1,
            v: v,
            r: r,
            s: s,
            extraSignature: abi.encode(merklePaths[0]),
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
        vm.deal(buyer1, totalPrice);
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

        assertEq(
            MerkleVerifier._computedRoot(buyOrderHashes[0], merklePaths[0]),
            merkleRoot,
            unicode"第一个订单路径无效"
        );
        assertEq(
            MerkleVerifier._computedRoot(buyOrderHashes[1], merklePaths[1]),
            merkleRoot,
            unicode"第二个订单路径无效"
        ); // 关键
        assertEq(
            MerkleVerifier._computedRoot(buyOrderHashes[2], merklePaths[2]),
            merkleRoot,
            unicode"第三个订单路径无效"
        ); // 关键
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
    ) internal view returns (Order memory) {
        return
            Order({
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
        return
            Order({
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

    function buildMerkleTree(
        bytes32[] memory leaves
    ) internal pure returns (bytes32 root, bytes32[][] memory paths) {
              require(leaves.length > 0, "No leaves");

        uint256 leafCount = leaves.length;
        paths = new bytes32[][](leafCount);

        // pos[i] 表示“第 i 个原始叶子在当前层的索引”
        uint256[] memory pos = new uint256[](leafCount);
        for (uint256 i = 0; i < leafCount; i++) {
            pos[i] = i;
        }

        // 当前层节点
        bytes32[] memory level = leaves;
        uint256 levelLen = leaves.length;

        while (levelLen > 1) {
            // 1) 先用当前层记录每个叶子的兄弟（如果有）
            for (uint256 i = 0; i < leafCount; i++) {
                uint256 idx = pos[i];
                uint256 sib = (idx & 1 == 0) ? idx + 1 : idx - 1; // 偶数取右，奇数取左
                if (sib < levelLen) {
                    paths[i] = _append(paths[i], level[sib]);
                }
            }

            // 2) 生成下一层
            uint256 parentLen = (levelLen + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](parentLen);

            for (uint256 k = 0; k < levelLen; k += 2) {
                if (k + 1 == levelLen) {
                    // 奇数个节点，最后一个直接晋级
                    nextLevel[k / 2] = level[k];
                } else {
                    (bytes32 left, bytes32 right) = _sort(level[k], level[k + 1]);
                    nextLevel[k / 2] = keccak256(abi.encodePacked(left, right));
                }
            }

            // 3) 所有叶子的“当前层位置”上移到父层
            for (uint256 i = 0; i < leafCount; i++) {
                pos[i] = pos[i] >> 1; // 等价于 /2
            }

            level = nextLevel;
            levelLen = parentLen;
        }

        root = level[0];
    }

    function signOrder(
        uint256 privateKey,
        Order memory order,
        SignatureVersion signtureVersion
    ) internal view returns (Input memory) {
        bytes32 orderHash = nftOrderManager._hashOrder(order, order.nonce);
        bytes32 domain = nftOrderManager.getDOMAIN_SEPARATOR();
        bytes32 hashToSign = keccak256(
            abi.encodePacked("\x19\x01", domain, orderHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashToSign);
        return
            Input({
                order: order,
                v: v,
                r: r,
                s: s,
                extraSignature: "",
                signatureVersion: signtureVersion,
                blockNumber: block.number
            });
    }

    // 辅助函数：向数组尾部添加元素（确保路径顺序为从叶子到根）
    function _append(
        bytes32[] memory arr,
        bytes32 value
    ) internal pure returns (bytes32[] memory) {
        bytes32[] memory newArr = new bytes32[](arr.length + 1);
        for (uint256 i = 0; i < arr.length; i++) {
            newArr[i] = arr[i];
        }
        newArr[arr.length] = value; // 新元素添加到尾部，保持层级顺序（从下到上）
        console.log(unicode"push部分",arr.length);
        console.logBytes32(value);
        return newArr;
    }
    function _sort(bytes32 a, bytes32 b) internal pure returns (bytes32, bytes32) {
        return a < b ? (a, b) : (b, a);
    }

    // 新增：最小用例测试，逐层级验证哈希一致性
    function testMerkleConsistencyWithContract() public {
        // 1. 准备测试数据（确保A < B < C）
        bytes32 A = 0x542c8b45be30a61071496414a843f0ccd604a1d16024d4d147337f3974dce448;
        bytes32 B = 0x4ebe3b51a140ac2e8d11768cc80b112ef2bcf33ea4b502e2bba266d4754899f4;
        bytes32 C = 0x16085b4b279a96f7a6dbc3ffa59bbf2ed1759e4754a855a8bc8d6db697a1a216;
        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = B; // 故意打乱顺序：B（中）、C（大）、A（小）
        leaves[1] = C;
        leaves[2] = A;

        // 2. 测试中构建Merkle树
        (bytes32 testRoot, bytes32[][] memory paths) = buildMerkleTree(leaves);
        console.logBytes32(testRoot);
        for(uint8 i=0;i<leaves.length;i++){
            console.log(unicode"节点路径",i);
            for(uint8 j=0;j<paths[i].length;j++){
                console.logBytes32( paths[0][j]);
            }
        }
        // 3. 用合约逻辑计算每个叶子的根哈希，验证一致性
        bytes32 contractRoot0 = MerkleVerifier._computedRoot(
            leaves[0],
            paths[0]
        );
        bytes32 contractRoot1 = MerkleVerifier._computedRoot(
            leaves[1],
            paths[1]
        );
        bytes32 contractRoot2 = MerkleVerifier._computedRoot(
            leaves[2],
            paths[2]
        );
        console.logBytes32( contractRoot0);
        console.logBytes32( contractRoot1);
        console.logBytes32( contractRoot2);

        // 4. 断言所有根哈希必须一致
        assertEq(testRoot, contractRoot0, unicode"叶子0的根哈希不匹配");
        assertEq(testRoot, contractRoot1, unicode"叶子1的根哈希不匹配");
    }
}
