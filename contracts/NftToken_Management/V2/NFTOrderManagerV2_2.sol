// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "../NFTOrderManager.sol";

contract NFTOrderManagerV2_2 is NFTOrderManager{
    
    // 添加版本标识
    string public constant VERSION = "2.2";
    
    function executeV2(
        Input calldata sell,
        Input calldata buy
    ) external payable setupExecution nonReentrant {
        _executeV2(sell, buy);
        _returnDustV2();
    }
    
    function _executeV2(
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
        require(_validateSignatures(buy, buyHash), "Buy failed authorization");
        
        (
            uint256 tokenId,
            uint256 amount,
            uint256 price,
            AssetType assetType
        ) = _canMatchOrdersV2(sell.order, buy.order);

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

    function _canMatchOrdersV2(
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
            require(
                policyManager.isPolicyWhitelisted(sell.matchingPolicy),
                "policy is not whitelist"
            );
            (canMatch, price, tokenId, amount, assetType) = IMatchingPolicy(
                sell.matchingPolicy
            ).canMatchMakerAsk(sell, buy);
        }
        else if (buy.createAT < sell.createAT) {
            require(
                policyManager.isPolicyWhitelisted(buy.matchingPolicy),
                "policy is not whitelist"
            );
            (canMatch, price, tokenId, amount, assetType) = IMatchingPolicy(
                buy.matchingPolicy
            ).canMatchMakerBid(buy, sell);
        }
        else {
            // 修复：时间戳相等时的处理
            require(
                policyManager.isPolicyWhitelisted(sell.matchingPolicy),
                "policy is not whitelist"
            );
            (canMatch, price, tokenId, amount, assetType) = IMatchingPolicy(
                sell.matchingPolicy
            ).canMatchMakerAsk(sell, buy);
        }

        require(canMatch, "Orders cannot be matched");
        return (tokenId, amount, price, assetType);
    }

    function _returnDustV2() private {
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
    
    function getVersion() external pure returns (string memory) {
        return VERSION;
    }
}