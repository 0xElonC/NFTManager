// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Input, Order} from "../struct/OrderStruct.sol";
import "./IExecutionDelegate.sol";
import "../policyManage/interfaces/IPolicyManager.sol";

interface INFTOrderManager {
    function nonces(address) external view returns (uint256);

    function initialize(
        address ownerAddress,
        IPolicyManager _policyManager,
        IExecutionDelegate _executionDelegate,
        address pool
    ) external;
    function setExecutionDelegate(IExecutionDelegate _executionDelegate) external;

    function setPolicyManager(IPolicyManager _policyManager) external;

    function execute(Input calldata sell, Input calldata buy)
        external
        payable;
}
