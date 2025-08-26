// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/INFTOrderManager.sol";
import "./policyManage/interfaces/IPolicyManager.sol";
import "./policyManage/interfaces/IMatchingPolicy.sol";
import "./interfaces/IExecutionDelegate.sol";
import "./utils/OrderEIP712.sol";
import "./utils/MerkleVerifier.sol";
import "../pool/interfaces/IETHPool.sol";

import {Order, AssetType, Input, Side, SignatureVersion, Fee, Execution} from "./struct/OrderStruct.sol";

contract NFTOrderManager is
    INFTOrderManager,
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IERC721Receiver,
    UUPSUpgradeable,
    OrderEIP712
{
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public orderCounter;
    /*storage */
    mapping(bytes32 => bool) public cancelOrFilled;
    mapping(address => uint256) public nonces;
    bool public isInternal;
    uint256 public balanceETH;

    /* Constants */
    uint256 public constant INVERSE_BASIS_POINT = 10_000;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant POOL = 0x101862DB513aC360aF6E0E954356b73F246E429a;
    uint256 private constant MAX_FEE_RATE = 250;

    /*Variables*/
    IPolicyManager public policyManager;
    IExecutionDelegate public executionDelegate;

    /* Governance Variables */
        /* Governance Variables */
    uint256 public feeRate;
    address public feeRecipient;

    address public governor;

    /*Event*/
    event OrderCreated(
        uint256 indexed orderId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        AssetType AssetType,
        uint256 price,
        uint256 quantity,
        uint256 vaildUntil,
        uint256 nonce
    );
    event OrderMatched(
        address indexed maker,
        address indexed taker,
        Order sell,
        bytes32 sellHash,
        Order buy,
        bytes32 buyHash
    );
    event OrderCancelled(bytes32 hash);
    event NonceIncremented(address indexed trader, uint256 newNonce);
    event NewExecutionDelegate(IExecutionDelegate indexed executionDelegate);
    event NewPolicyManager(IPolicyManager indexed policyManager);
    event NewGovernor(address governor);
    event NewFeeRate(uint256 feeRate);
    event NewFeeRecipient(address feeRecipient);

    constructor() {
        _disableInitializers();
    }

    modifier internalCall() {
        require(isInternal, "Unsafe call");
        _;
    }

    modifier setupExecution() {
        require(!isInternal, "unsafe call");
        balanceETH = msg.value;
        isInternal = true;
        _;
        balanceETH = 0;
        isInternal = false;
    }

    function setExecutionDelegate(
        IExecutionDelegate _executionDelegate
    ) external onlyOwner {
        require(
            address(_executionDelegate) != address(0),
            "Address cannot be zero"
        );
        executionDelegate = _executionDelegate;
        emit NewExecutionDelegate(executionDelegate);
    }
        function setPolicyManager(
        IPolicyManager _policyManager
    ) external onlyOwner {
        require(
            address(_policyManager) != address(0),
            "Address cannot be zero"
        );
        policyManager = _policyManager;
        emit NewPolicyManager(policyManager);
    }
    function setFeeRate(uint256 _feeRate)
        external
    {
        require(msg.sender == governor, "Fee rate can only be set by governor");
        require(_feeRate <= MAX_FEE_RATE, "Fee cannot be more than 2.5%");
        feeRate = _feeRate;
        emit NewFeeRate(feeRate);
    }

    function setFeeRecipient(address _feeRecipient)
        external
        onlyOwner
    {
        feeRecipient = _feeRecipient;
        emit NewFeeRecipient(feeRecipient);
    }

    // required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        address ownerAddress,
        IPolicyManager _policyManager,
        IExecutionDelegate _executionDelegate
    ) external initializer {
        __Ownable_init(ownerAddress);
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        policyManager = _policyManager;
        executionDelegate = _executionDelegate;
        isInternal = false; // 原来写在声明处的值
        balanceETH = 0;
        DOMAIN_SEPARATOR = _hashDomain(
            EIP712Domain({
                name: "XY",
                version: "1.0",
                chainId: block.chainid,
                verifyingContract: address(this)
            })
        );
        orderCounter = 1;
    }

    /**
     * 在卖单和买单之间执行一笔交易。
     * @param sell 包含卖单详情的输入结构体。
     * @param buy 包含买单详情的输入结构体。*/
    function execute(
        Input calldata sell,
        Input calldata buy
    ) external payable setupExecution nonReentrant {
        _execute(sell, buy);
        _returnDust();
    }

    function blukExecute(
        Execution[] calldata executions
    ) external payable setupExecution {
        /*
        uint256 executionsLength = executions.length;
        for(uint8 i=0;i<executionsLength,i++){
            bytes32 memroy data = abi.encodeWithSelector(_execute.selector,executions.sell,executions.buy);
            (bool success,) = address(this).delegatecall(data);
        }
        */
        uint256 executionsLength = executions.length;
        if (executionsLength == 0) {
            revert("No order to execute");
        }
        for (uint8 i = 0; i < executionsLength; i++) {
            assembly ("memory-safe") {
                let memPoint := mload(0x40)

                let order_localtion := calldataload(
                    add(executions.offset, mul(i, 0x20))
                )
                let order_point := add(executions.offset, order_localtion)

                let size
                switch eq(add(i, 0x01), executionsLength)
                case 1 {
                    size := sub(calldatasize(), order_point)
                }
                default {
                    let next_order_localtion := calldataload(
                        add(executions.offset, mul(add(i, 0x01), 0x20))
                    )
                    let next_order_point := add(
                        executions.offset,
                        next_order_localtion
                    )
                    size := sub(next_order_point, order_point)
                }

                mstore(
                    memPoint,
                    0x42d9f81000000000000000000000000000000000000000000000000000000000
                )
                calldatacopy(add(0x04, memPoint), order_point, size)
                let result := delegatecall(
                    gas(),
                    address(),
                    memPoint,
                    add(size, 0x04),
                    0,
                    0
                )
            }
        }
        _returnDust();
    }

    /**
     * 执行一笔由卖出订单和买入订单组成的交易。
     * @param sell 包含卖出订单详情的输入结构体。
     * @param buy 包含买入订单详情的输入结构体
     */
    function _execute(
        Input calldata sell,
        Input calldata buy
    ) public payable internalCall {
        require(sell.order.side == Side.Sell);
        bytes32 sellHash = _hashOrder(sell.order, nonces[sell.order.trader]);
        bytes32 buyHash = _hashOrder(buy.order, nonces[buy.order.trader]);

        require(
            _vaildataOrderParameters(sell.order, sellHash),
            "sell has invalid parameters"
        );
        require(
            _vaildataOrderParameters(buy.order, buyHash),
            "buy has invalid parameters"
        );
        require(
            _validateSignatures(sell, sellHash),
            "Sell failed authorization"
        );
        require(_validateSignatures(buy, buyHash), "Buy failed autonrization");
        (
            uint256 tokenId,
            uint256 amount,
            uint256 price,
            AssetType assetType
        ) = _canMatchOrders(sell.order, buy.order);

        cancelOrFilled[sellHash] = true;
        cancelOrFilled[buyHash] = true;
        _executeFundsTransfer(
            sell.order.trader,
            buy.order.trader,
            sell.order.paymentToken,
            sell.order.fees,
            buy.order.fees,
            price
        );
        _executeTokenTransfer(
            sell.order.trader,
            buy.order.trader,
            sell.order.nftContract,
            tokenId,
            amount,
            assetType
        );

        emit OrderMatched(
            sell.order.createAT > buy.order.createAT
                ? sell.order.trader
                : buy.order.trader,
            buy.order.createAT <= sell.order.createAT
                ? sell.order.trader
                : buy.order.trader,
            sell.order,
            sellHash,
            buy.order,
            buyHash
        );
    }

    /**
     * 检查订单参数的有效性。
     * @param order 包含订单详情的订单结构体
     * @param orderhash  用于验证的订单哈希值
     */
    function _vaildataOrderParameters(
        Order calldata order,
        bytes32 orderhash
    ) internal view returns (bool) {
        return (/* Order must have a trader. */
        (order.trader != address(0)) &&
            (cancelOrFilled[orderhash] == false) &&
            (order.createAT <= block.timestamp) &&
            (order.validUntil > block.timestamp));
    }

    /**
     *  验证给定订单输入及哈希值的签名。
     * @param input 包含订单及签名详情的输入结构体。
     * @param orderHash 用于验证签名的订单的哈希值。
     */
    function _validateSignatures(
        Input calldata input,
        bytes32 orderHash
    ) internal view returns (bool) {
        if (input.order.trader == msg.sender) {
            return true;
        }
        /**check user authorization */
        if (
            !_validateUserAuthorization(
                orderHash,
                input.order.trader,
                input.v,
                input.r,
                input.s,
                input.signatureVersion,
                input.extraSignature
            )
        ) {
            return false;
        }
        return true;
    }

    /**
     * 使用提供的签名和签名版本验证订单的用户授权。
     * @param orderHash 要授权的订单的哈希值。
     * @param trader 签署订单的交易者地址。
     * @param v 签名的恢复字节。
     * @param r ECDSA 签名对的一半。
     * @param s ECDSA 签名对的一半。
     * @param signatureVersion 签名的版本（单个或批量）。
     * @param extraSignature 批量授权的附加签名数据。
     */
    function _validateUserAuthorization(
        bytes32 orderHash,
        address trader,
        uint8 v,
        bytes32 r,
        bytes32 s,
        SignatureVersion signatureVersion,
        bytes calldata extraSignature
    ) internal view returns (bool) {
        bytes32 hashToSign;
        if (signatureVersion == SignatureVersion.Single) {
            /**single listing authentication:Order signed by trader */
            hashToSign = _hashToSign(orderHash);
        } else if (signatureVersion == SignatureVersion.Bulk) {
            /**Bluk listing authentication:Markle root of orders signed by trader */
            bytes32[] memory marklePath = abi.decode(
                extraSignature,
                (bytes32[])
            );

            bytes32 computedRoot = MerkleVerifier._computedRoot(
                orderHash,
                marklePath
            );
            hashToSign = _hashToSignRoot(computedRoot);
        }
        return _verify(trader, hashToSign, v, r, s);
    }

    /**
     * 一致性匹配
     * @param sell sell
     * @param buy  buy
     */
    function _canMatchOrders(
        Order calldata sell,
        Order calldata buy
    )
        internal
        view
        returns (
            uint256 tokenId,
            uint256 amount,
            uint256 price,
            AssetType assetType
        )
    {
        bool canMatch;

        if (sell.createAT < buy.createAT) {
            //seller is maker
            require(
                policyManager.isPolicyWhitelisted(sell.matchingPolicy),
                "policy is not whitelist"
            );
            (canMatch, price, tokenId, amount, assetType) = IMatchingPolicy(
                sell.matchingPolicy
            ).canMatchMakerAsk(sell, buy);
        }
        if (buy.createAT < sell.createAT) {
            //buyer is maker
            require(
                policyManager.isPolicyWhitelisted(buy.matchingPolicy),
                "policy is not whitelist"
            );
            (canMatch, price, tokenId, amount, assetType) = IMatchingPolicy(
                buy.matchingPolicy
            ).canMatchMakerAsk(sell, buy);
        }

        require(canMatch, "Orders cannot be matched");
        return (tokenId, amount, price, assetType);
    }

    /**
     * * 执行交易的 GAS 费用
     * @param seller 卖家的地址。
     * @param buyer 买家地址
     * @param paymentToken 支付代币地址
     * @param sellerFees 由卖家支付的费用数组.
     * @param buyerFees 由买家支付的费用数组.
     * @param price 交易的价格
     */
    function _executeFundsTransfer(
        address seller,
        address buyer,
        address paymentToken,
        Fee[] calldata sellerFees,
        Fee[] calldata buyerFees,
        uint256 price
    ) internal internalCall {
        if (paymentToken == address(0)) {
            require(msg.sender == buyer, "cannot use ETH");
            require(balanceETH >= price, "Insufficient value");
            balanceETH -= price;
        }

        uint256 sellerFeePaid = _transferFees(
            sellerFees,
            paymentToken,
            buyer,
            price,
            true
        );
        uint256 buyerFeePaid = _transferFees(
            buyerFees,
            paymentToken,
            buyer,
            price,
            false
        );
        if (paymentToken == address(0)) {
            //Need to account for buyer fees paid on top of the price.
            balanceETH -= buyerFeePaid;
        }
        _transferTo(paymentToken, buyer, seller, price - sellerFeePaid);
    }

    function _executeTokenTransfer(
        address seller,
        address buyer,
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        AssetType assertType
    ) internal {
        if (assertType == AssetType.ERC721) {
            executionDelegate.transferERC721(
                seller,
                buyer,
                nftContract,
                tokenId
            );
        }
        if (assertType == AssetType.ERC1155) {
            executionDelegate.transferERC1155(
                seller,
                buyer,
                nftContract,
                tokenId,
                amount
            );
        }
    }

    /**
     * 以以太币或 WETH 形式收取费用
     * @param fees fees
     * @param paymentToken 要支付的代币地址
     * @param from  收取费用的地址
     * @param price 代币价格
     * @param protocolFee  总费用支付额
     */
    function _transferFees(
        Fee[] calldata fees,
        address paymentToken,
        address from,
        uint256 price,
        bool protocolFee
    ) internal returns (uint256) {
        uint256 totalFee = 0;

        /* Take protocol fee if enabled. */
        if (feeRate > 0 && protocolFee) {
            uint256 fee = (price * feeRate) / INVERSE_BASIS_POINT;
            _transferTo(paymentToken, from, feeRecipient, fee);
            totalFee += fee;
        }

        /* Take order fees. */
        for (uint8 i = 0; i < fees.length; i++) {
            uint256 fee = (price * fees[i].rate) / INVERSE_BASIS_POINT;
            _transferTo(paymentToken, from, fees[i].recipient, fee);
            totalFee += fee;
        }

        require(totalFee <= price, "Fees are more than the price");

        return totalFee;
    }

    /**
     * 调用executionDelegate 发起交易函数
     * @param paymentToken 代币地址
     * @param from  发起方
     * @param to   接收方
     * @param amount token数量
     */
    function _transferTo(
        address paymentToken,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) {
            return;
        }
        if (paymentToken == address(0)) {
            //Transfer funds in ETH
            require(to != address(0), "transfer to zero addresss");
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else if (paymentToken == WETH) {
            //Transfer funds in WETH
            executionDelegate.transferERC20(from, to, WETH, amount);
        } else if (paymentToken == POOL) {
            bool success = IETHPool(POOL).transferFrom(from, to, amount);
            require(success, "Pool transfer failed");
        } else {
            revert("Error PaymentToken");
        }
    }

    /**
     * @dev 取消订单，阻止其被匹配。此操作须由该订单的交易员发起。
     * @param order Order to cancel
     */
    function cancelOrder(Order calldata order) public {
        /* Assert sender is authorized to cancel order. */
        require(msg.sender == order.trader, "Not sent by trader");

        bytes32 hash = _hashOrder(order, nonces[order.trader]);

        require(!cancelOrFilled[hash], "Order cancelled or filled");

        /* Mark order as cancelled, preventing it from being matched. */
        cancelOrFilled[hash] = true;
        emit OrderCancelled(hash);
    }

    /**
     * @dev Cancel multiple orders
     * @param orders Orders to cancel
     */
    function cancelOrders(Order[] calldata orders) external {
        for (uint8 i = 0; i < orders.length; i++) {
            cancelOrder(orders[i]);
        }
    }
        /**
     * @dev Cancel all current orders for a user, preventing them from being matched. Must be called by the trader of the order
     */
    function incrementNonce() external {
        nonces[msg.sender] += 1;
        emit NonceIncremented(msg.sender, nonces[msg.sender]);
    }



    function getNonce() external view returns (uint256) {
        return nonces[msg.sender];
    }

    function getDOMAIN_SEPARATOR() external view returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        // 返回接口选择器，表示成功接收
        return this.onERC721Received.selector;
    }

    function _verify(
        address signer,
        bytes32 originHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public pure returns (bool) {
        require(v == 27 || v == 28, "Invalid v parameter");
        address recoverSign = ecrecover(originHash, v, r, s);
        if (recoverSign == address(0)) {
            return false;
        } else {
            return signer == recoverSign;
        }
    }

    /**
     * @dev 将剩余的以太币返还给“批量执行”或“执行”操作。
     */
    function _returnDust() private {
        uint256 _remainingETH = balanceETH;
        assembly ("memory-safe") {
            if gt(_remainingETH, 0) {
                let callState := call(
                    gas(),
                    caller(),
                    _remainingETH,
                    0,
                    0,
                    0,
                    0
                )
                if iszero(callState) {
                    revert(0, 0)
                }
            }
        }
    }


    // 接收ETH回调
    receive() external payable {}
}
