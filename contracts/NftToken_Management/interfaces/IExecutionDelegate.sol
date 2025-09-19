// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IExecutionDelegate {
    
    function approveContract(address _contract) external;
    function denyContract(address _contract) external;
    function revokeApproval() external;
    function grantApproval() external;
    function transferERC20(address from,address to,address token,uint256 amount) external;

    function transferERC721(address from,address to,address token,uint256 tokenId) external;

    function transferERC1155(address from,address to,address token,uint256 tokenId,uint256 amount)external;
}