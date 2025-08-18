// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IETHPool.sol";
contract ETHPool is IETHPool,OwnableUpgradeable,UUPSUpgradeable{
    address private EXCHANGE;

    mapping(address => uint256) private _balances;

    string public constant name = "ETH Pool";
    string constant symbol = "";
    constructor(){
        _disableInitializers();
    }
    function decimals() external pure returns (uint8) {
        return 18;
    }
    function initialize(address ownerAddress) external initializer{
        __Ownable_init(ownerAddress);
    }

    function _authorizeUpgrade(address)internal override onlyOwner{}

    function totalSupply() external view returns(uint256){
        return address(this).balance;
    }

    function balanceOf(address account) external view returns(uint256){
        return _balances[account];
    }

    function deposit() public payable{
        _balances[msg.sender] += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external{
        require(_balances[msg.sender]>=amount,"Insufficient funds");
        _balances[msg.sender] -= amount;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        emit Transfer(msg.sender,address(0), amount);
    }

    function transferFrom(address from,address to,uint256 amount) external returns(bool){
        if(msg.sender!=EXCHANGE){
            revert("Unauthorized transfer");
        }
        _transfer(from,to,amount);
        return true;
    }

    function _transfer(address from,address to,uint256 amount)private {
        require(to != address(0),"Cannot transfer to 0x addresss ");
        require(_balances[from]>=amount,"Insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;

        emit Transfer(from,to,amount);
    }

    receive() external payable {
        deposit();
    }

}