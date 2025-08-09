// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./policyManage/interfaces/IPolicyManager.sol";
import "./policyManage/interfaces/IMatchingPolicy.sol";
import "./interfaces/IExecutionDelegate.sol";
import "./utils/EIP712.sol";
import "./utils/MerkleVerifier.sol";

import {Order, AssetType, Input, Side, SignatureVersion,Fee} from "./struct/OrderStruct.sol";

contract NFTOrderManager is
    Initializable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    IERC721Receiver,
    EIP712
{
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public orderCounter;
    /*storage */
    mapping(bytes32 => bool) public cancelOrFilled;
    mapping(address => uint256) public nonces;
    bool public isInternal = false;
    uint256 public balanceETH = 0;

    /* Constants */
    string public constant NAME = "XY";
    string public constant VERSION = "1.0";
    uint256 public constant INVERSE_BASIS_POINT = 10_000;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /*Variables*/
    IPolicyManager public policyManager;
    IExecutionDelegate public executionDelegate;

    /* Governance Variables */
    uint256 public feeRate;
    address public feeRecipient;
 
    /*Event*/
    event OrderCreated(
        uint256 indexed orderId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        AssetType AssetType,
        uint256 price,
        uint256 quantity,
        uint256 vaildUntil
    );

    /*modifier*/
    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender));
        _;
    }

    modifier internalCall() {
        require(isInternal,"Unsafe call");
        _;
    }

    modifier setupExecution() {
        require(!isInternal,"unsafe call");
        balanceETH = msg.value;
        isInternal = true;
        _;
        balanceETH = 0;
        isInternal = false;
    }

    function initialize(uint _blockRange) external initializer {
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        orderCounter = 1;
    }

    /**
     * Executes a trade between a sell order and a buy order.
     * @param sell The input struct containing the sell order details.
     * @param buy The input struct containing the buy order details.
     */
    function execute(
        Input calldata sell,
        Input calldata buy
    ) external payable nonReentrant {
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

        require( _validateSignatures(sell, sellHash),"Sell failed authorization");
        require(_validateSignatures(buy, buyHash), "Buy failed autonrization");

        (uint256 price,uint256 tokenId,uint256 amount, AssetType assetType) = _canMatchOrders(sell.order, buy.order);

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
    }

    /**
     * Checks the validity of order parameters.
     * @param order The order struct containing order details.
     * @param orderhash The hash of the order used for validation.
     */
    function _vaildataOrderParameters(
        Order calldata order,
        bytes32 orderhash
    ) internal view returns (bool) {
        return (/* Order must have a trader. */
        (order.trader != address(0)) &&
            (cancelOrFilled[orderhash] == false) &&
            (order.createAT < block.timestamp) &&
            (order.validUntil == 0 || order.validUntil < block.timestamp));
    }

    /**
     * Validates the signature for the given order input and hash.
     * @param input The input struct containing order and signature details.
     * @param orderHash The hash of the order used for signature validation.
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
    }

    /**
     * Validates user authorization for an order using the provided signature and signature version.
     * @param orderHash The hash of the order to be authorized.
     * @param trader The address of the trader who signed the order.
     * @param v The recovery byte of the signature.
     * @param r Half of the ECDSA signature pair.
     * @param s Half of the ECDSA signature pair.
     * @param signatureVersion The version of the signature (Single or Bulk).
     * @param extraSignature Additional signature data for bulk authorization.
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
     * verity match
     * @param sell sell
     * @param buy  buy 
     * @return tokenId 
     * @return amount 
     * @return price 
     * @return assetType 
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
        return (price, tokenId, amount, assetType);
    }

    function _executeFundsTransfer(
        address seller,
        address buyer,
        address paymentToken,
        Fee[] calldata sellerFees,
        Fee[] calldata buyerFees,
        uint256 price
    )internal {
        if(paymentToken == address(0)){
            require(msg.sender == buyer,"cannot use ETH");
            require(balanceETH >= price,"Insufficient value");
            balanceETH -= price;
        }

        uint256 sellerFeePaid = _transferFees(sellerFees,paymentToken,buyer,price,true);
        uint256 buyerFeePaid = _transferFees(buyerFees,paymentToken,buyer,price,false);
        if(paymentToken == address(0)){
            //Need to account for buyer fees paid on top of the price.
            balanceETH -= buyerFeePaid;
        }


    }

    /**
     * charge a fee in ETH or WETH
     * @param Fees fees 
     * @param paymentToken address of token to pay in
     * @param from address to charge fees
     * @param price price to token
     * @param protocolFee  total fees paid
     */
    function _transferFees(
        Fee[] memory Fees,
        address paymentToken,
        address from,
        uint256 price,
        bool protocolFee
        ) internal returns(uint256) {
        uint256 totalFee = 0;
        if(protocolFee && feeRate > 0){
            uint256 fee = (price * feeRate) / INVERSE_BASIS_POINT;
            _transferTo(paymentToken,from,feeRecipient,fee);
            totalFee += fee;
        }

        //Take order fees
        for(uint256 i =0 ;i<Fees.length;i++){
            uint256 fee = (price * Fees[i].rate) / INVERSE_BASIS_POINT;
            _transferTo(paymentToken,from,feeRecipient,fee);
            totalFee += fee;
        }

        require(totalFee<= price," Fees are more than the price");

        return totalFee;
    }

    /**
     * Determine the transaction token to execute the transaction.
     * @param paymentToken paymentToken 
     * @param from  from address
     * @param to   to address 
     * @param amount token amount
     */
    function _transferTo(
        address paymentToken,
        address from,
        address to,
        uint256 amount
    )internal {
        if(amount == 0 ){
            return;
        }
        if(paymentToken == address(0)){
            //Transfer funds in ETH
            require(to != address(0),"transfer to zero addresss");
            (bool success,) = payable(to).call{value:amount}("");
            require(success,"ETH transfer failed");
        }else if(paymentToken == WETH){
            //Transfer funds in WETH
            executionDelegate.transferERC20(from,to,WETH,amount);
        }else{
            revert("Error PaymentToken");
        }
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

    // 接收ETH回调
    receive() external payable {
    }

    function _verify(
        address signer,
        bytes32 originHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (bool) {
        require(v == 27 || v == 28, "Invalid v parameter");
        address recoverSign = ecrecover(originHash, v, r, s);
        if (recoverSign == address(0)) {
            return false;
        } else {
            return signer == recoverSign;
        }
    }
}
