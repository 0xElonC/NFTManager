// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import { IExecutionDelegate } from "./interfaces/IExecutionDelegate.sol";

contract ExecutionDelegate is IExecutionDelegate, Ownable{
    using Address for address;

    mapping(address => bool) public contracts;
    mapping(address => bool) public revokedApproval;

    modifier approvedContract() {
        require(contracts[msg.sender] == true,"Contract is not approved to make transfers");
        _; 
    }

    event ApproveContract(address indexed _contract);
    event ContractDenied(address indexed _contract);

    event RevokeApproval(address indexed user);
    event GrantApproval(address indexed user);

    constructor(address initialOwner)Ownable(initialOwner){}

    /**
     * @dev Approve contract to call transfer functions
     * @param _contract address of contract to approve
     */
    function approveContract(address _contract) onlyOwner external {
        contracts[_contract] = true;
        emit ApproveContract(_contract);
    }

    /**
     * @dev Revoke approval of contract to call transfer functions
     * @param _contract address of contract to revoke approval
     */
    function denyContract(address _contract) onlyOwner external {
        contracts[_contract] = false;
        emit ContractDenied(_contract);
    }

    /**
     * @dev Block contract from making transfers on-behalf of a specific user
     */
    function revokeApproval() external {
        revokedApproval[msg.sender] = true;
        emit RevokeApproval(msg.sender);
    }

    /**
     * @dev Allow contract to make transfers on-behalf of a specific user
     */
    function grantApproval() external {
        revokedApproval[msg.sender] = false;
        emit GrantApproval(msg.sender);
    }
    function transferERC20(
        address from,
        address to,
        address token,
        uint256 amount
    ) approvedContract external {
        require(revokedApproval[from] == false,"User has revoked approval");
        bytes memory data = abi.encodeWithSelector(IERC20.transferFrom.selector,from,to,amount);
        bytes memory returnData = token.functionCall(data);
        if(returnData.length > 0){
            require(abi.decode(returnData,(bool)),"ERC20 transfer failed");
        }
    }
}