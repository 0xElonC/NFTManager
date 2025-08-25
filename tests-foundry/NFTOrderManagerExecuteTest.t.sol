// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/NftToken_Management/NFTOrderManager.sol";
import "../contracts/TestERC721.sol";
import "../contracts/NftToken_Management/struct/OrderStruct.sol";
import "../contracts/NftToken_Management/utils/OrderEIP712.sol";
import "../contracts/NftToken_Management/ExecutionDelegate.sol";
import "../contracts/NftToken_Management/policyManage/PolicyManager.sol";
import "../contracts/NftToken_Management/policyManage/interfaces/IMatchingPolicy.sol";
import "../contracts/NftToken_Management/policyManage/matchingPolices/StandardPolicyERC721.sol";

// 测试合约
contract NFTOrderManagerExecuteTest is Test, OrderEIP712 {
    // 核心合约
    NFTOrderManager public nftOrderManager;
    ExecutionDelegate public executionDelegate;
    PolicyManager public policyManager;
    TestERC721 public nft;
    StandardPolicyERC721 public standardPolicyERC721;

    // 测试账户
    uint256 public sellerPK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public buyerPK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address public seller;
    address public buyer;
    address public owner;

    // 常量
    uint256 public constant TOKEN_ID = 1;
    uint256 public constant PRICE = 1000000000000000000 wei;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {
    seller = vm.addr(sellerPK);
    buyer  = vm.addr(buyerPK);
    owner  = address(this);

    executionDelegate = new ExecutionDelegate(owner);
    standardPolicyERC721 = new StandardPolicyERC721();

    address[] memory whitelist = new address[](1);
    whitelist[0] = address(standardPolicyERC721);
    policyManager = new PolicyManager(owner, whitelist);

    // ✅ 部署实现合约
    NFTOrderManager impl = new NFTOrderManager();

    // ✅ 构造初始化数据
    bytes memory initData = abi.encodeCall(
        NFTOrderManager.initialize,
        (owner, IPolicyManager(address(policyManager)), IExecutionDelegate(address(executionDelegate)))
    );

    // ✅ 用 ERC1967Proxy 包装，并在构造时初始化
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

    // ✅ 把代理地址当作主合约来用
    nftOrderManager = NFTOrderManager(payable(address(proxy)));

    // 部署测试 NFT 并铸造
    nft = new TestERC721("TestNFT", "TNFT", seller);
    vm.prank(seller);
    nft.mint(seller);

    // 卖家授权给 ExecutionDelegate
    vm.prank(seller);
    nft.setApprovalForAll(address(executionDelegate), true);

    executionDelegate.approveContract(address(nftOrderManager));

    vm.deal(buyer, 2 ether);
}

    // 辅助函数：创建卖单
    function _createSellOrder() internal view returns (Order memory) {
        Fee[] memory fees = new Fee[](0); 
        return Order({
            trader: seller,
            side: Side.Sell,
            matchingPolicy: address(standardPolicyERC721),
            nftContract: address(nft),
            tokenId: TOKEN_ID,
            AssetType: AssetType.ERC721,
            amount: 1,
            paymentToken: address(0), // 使用 ETH 支付
            price: PRICE,
            validUntil: block.timestamp + 1 days, // 有效期 1 天
            createAT: block.timestamp , // 订单创建时间（早于当前）
            fees: fees,
            extraParams: "",
            nonce: nftOrderManager.nonces(seller) // 使用当前 nonce
        });
    }

    // 辅助函数：创建买单
    function _createBuyOrder() internal view returns (Order memory) {
        Fee[] memory fees = new Fee[](0);
        return Order({
            trader: buyer,
            side: Side.Buy,
            matchingPolicy: address(standardPolicyERC721),
            nftContract: address(nft),
            tokenId: TOKEN_ID,
            AssetType: AssetType.ERC721,
            amount: 1,
            paymentToken: address(0), // 使用 ETH 支付
            price: PRICE,
            validUntil: block.timestamp + 1 days,
            createAT: block.timestamp,  // 买单创建时间（晚于卖单）
            fees: fees,
            extraParams: "",
            nonce: nftOrderManager.nonces(seller)
        });
    }

    // 辅助函数：签名订单
    function _signOrder(uint256 pk, Order memory order) internal view returns (Input memory) {
        // 计算订单哈希（包含 nonce）
        bytes32 orderHash = nftOrderManager._hashOrder(order, nftOrderManager.nonces(order.trader));
        bytes32 domain = nftOrderManager.getDOMAIN_SEPARATOR();
        bytes32 hashToSigh = keccak256(abi.encodePacked("\x19\x01",domain,orderHash));
        // 用私钥签名
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hashToSigh);
        return Input({
            order: order,
            v: v,
            r: r,
            s: s,
            extraSignature: "",
            signatureVersion: SignatureVersion.Single,
            blockNumber: block.number
        });
    }

    // 测试 1：正常执行交易（买卖订单匹配成功）
    function testExecuteSuccess() public {
        console.log("----testExecuteSuccess");
        // 1. 创建并签名订单
        Order memory sellOrder = _createSellOrder();
        vm.warp(block.timestamp + 1 hours);
        Order memory buyOrder = _createBuyOrder();
        Input memory sellInput = _signOrder(sellerPK, sellOrder);
        Input memory buyInput = _signOrder(buyerPK, buyOrder);

        // 2. 记录执行前状态
        uint256 sellerEthBefore = seller.balance;
        uint256 buyerEthBefore = buyer.balance;
        address ownerBefore = nft.ownerOf(TOKEN_ID);

        // 3. 买家调用 execute 执行交易
        vm.prank(buyer);
        nftOrderManager.execute{value: PRICE}(sellInput, buyInput);

        // 4. 验证结果
        // 4.1 NFT 所有权转移给买家
        assertEq(nft.ownerOf(TOKEN_ID), buyer, unicode"NFT 未转移给买家");
        // 4.2 卖家收到 ETH（扣除 gas 前）
        assertGe(seller.balance, sellerEthBefore, unicode"卖家未收到 ETH");
        // 4.3 买家 ETH 减少（支付价格）
        assertLe(buyer.balance, buyerEthBefore - PRICE, unicode"买家 ETH 未减少");
        // 4.4 订单被标记为已完成
        bytes32 sellHash = nftOrderManager._hashOrder(sellOrder,nftOrderManager.getNonce());
        bytes32 buyHash = nftOrderManager._hashOrder(buyOrder, 0);
        assertEq(nftOrderManager.cancelOrFilled(sellHash), true, unicode"卖单未标记为已完成");
        assertEq(nftOrderManager.cancelOrFilled(buyHash), true, unicode"买单未标记为已完成");
    }

    // 测试 2：卖单签名无效时执行失败
    function testExecuteRevertWhenSellSignatureInvalid() public {
        // 创建订单
        Order memory sellOrder = _createSellOrder();
        Order memory buyOrder = _createBuyOrder();
        // 用错误的私钥签名卖单（买家私钥签卖单）
        Input memory sellInput = _signOrder(buyerPK, sellOrder); 
        Input memory buyInput = _signOrder(buyerPK, buyOrder);

        // 预期失败：卖单签名验证失败
        vm.expectRevert("Sell failed authorization");
        vm.prank(buyer);
        nftOrderManager.execute{value: PRICE}(sellInput, buyInput);
    }

    // 测试 3：订单价格不匹配时执行失败
    function testExecuteRevertWhenPriceMismatch() public {
        // 创建卖单（价格 1 ETH）和买单（价格 0.5 ETH）
        Order memory sellOrder = _createSellOrder();
        Order memory buyOrder = _createBuyOrder();
        buyOrder.price = 0.5 ether; // 价格不匹配

        Input memory sellInput = _signOrder(sellerPK, sellOrder);
        Input memory buyInput = _signOrder(buyerPK, buyOrder);

        // 预期失败：订单无法匹配
        vm.expectRevert("Orders cannot be matched");
        vm.prank(buyer);
        nftOrderManager.execute{value: 0.5 ether}(sellInput, buyInput);
    }

    // 测试 4：卖单已过期时执行失败
    function testExecuteRevertWhenSellOrderExpired() public {
        Order memory sellOrder = _createSellOrder();
        vm.warp(block.timestamp + 2 days); // 已过期
        Order memory buyOrder = _createBuyOrder();

        Input memory sellInput = _signOrder(sellerPK, sellOrder);
        Input memory buyInput = _signOrder(buyerPK, buyOrder);

        // 预期失败：卖单参数无效（已过期）
        vm.expectRevert("sell has invalid parameters");
        vm.prank(buyer);
        nftOrderManager.execute{value: PRICE}(sellInput, buyInput);
    }

    // 测试 5：未授权 NFT 转移时执行失败
    function testExecuteRevertWhenNoNFTApproval() public {
        // 卖家撤销授权
        vm.prank(seller);
        nft.approveALL(address(nftOrderManager), false);

        // 创建并签名订单
        Order memory sellOrder = _createSellOrder();
        Order memory buyOrder = _createBuyOrder();
        Input memory sellInput = _signOrder(sellerPK, sellOrder);
        Input memory buyInput = _signOrder(buyerPK, buyOrder);

        // 预期失败：执行代理无法转移 NFT（具体错误取决于 ExecutionDelegate 实现）
        vm.expectRevert();
        vm.prank(buyer);
        nftOrderManager.execute{value: PRICE}(sellInput, buyInput);
    }

    // 测试 6：支付 ETH 不足时执行失败
    function testExecuteRevertWhenEthInsufficient() public {
        Order memory sellOrder = _createSellOrder();
        Order memory buyOrder = _createBuyOrder();
        Input memory sellInput = _signOrder(sellerPK, sellOrder);
        Input memory buyInput = _signOrder(buyerPK, buyOrder);

        // 买家只支付 0.5 ETH（不足 1 ETH）
        vm.expectRevert("Insufficient value");
        vm.prank(buyer);
        nftOrderManager.execute{value: 0.5 ether}(sellInput, buyInput);
    }
}