// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IExecutionDelegate {
    
    function approveContract(address _contract) external;
    function denyContract(address _contract) external;
    function revokeApproval() external;
    function grantApproval() external;
    function transferERC20(address token,address from,address to, uint256 amount) external;
}