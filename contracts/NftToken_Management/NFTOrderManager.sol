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
import "./utils/EIP712.sol";
import "./utils/MerkleVerifier.sol";

import {Order, AssetType, Input, Side, SignatureVersion} from "./struct/OrderStruct.sol";

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

    /* Constants */
    string public constant NAME = "XY";
    string public constant VERSION = "1.0";
    uint256 public constant INVERSE_BASIS_POINT = 10_000;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /*Variables*/
    IPolicyManager public policyManager;

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

    function initialize(uint _blockRange) external initializer {
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        orderCounter = 1;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender));
        _;
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

        require(
            _validateSignatures(sell, sellHash),
            "Sell failed authorization"
        );
        require(_validateSignatures(buy, buyHash), "Buy failed autonrization");
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
            require(policyManager.isPolicyWhitelisted(sell.matchingPolicy),"policy is not whitelist");
            (canMatch,price,tokenId,amount,assetType) = IMatchingPolicy(sell.matchingPolicy).canMatchMakerAsk(sell,buy);
        }
        if(buy.createAT < sell.createAT){
            //buyer is maker
            require(policyManager.isPolicyWhitelisted(buy.matchingPolicy),"policy is not whitelist");
            (canMatch,price,tokenId,amount,assetType) = IMatchingPolicy(buy.matchingPolicy).canMatchMakerAsk(sell,buy);
        }

        require(canMatch,"Orders cannot be matched");
        return (price, tokenId, amount, assetType);
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
        revert("Do not send ETH directly");
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
