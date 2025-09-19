// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IPolicyManager} from "./interfaces/IPolicyManager.sol";

contract PolicyManager is IPolicyManager, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _whitelistedPolicies;    
    constructor(address initialOwner, address[] memory initialPolicies) Ownable(initialOwner) {

        for (uint256 i = 0; i < initialPolicies.length; i++) {
            _whitelistedPolicies.add(initialPolicies[i]);
            emit PolicyWhitelisted(initialPolicies[i]);
        }
    }

    event PolicyRemoved(address indexed policy);
    event PolicyWhitelisted(address indexed policy);

    function addPolicy(address policy) external override onlyOwner {
        require(!_whitelistedPolicies.contains(policy), "Already whitelisted");
        _whitelistedPolicies.add(policy);
        emit PolicyWhitelisted(policy);
    }

    function removePolicy(address policy) external override onlyOwner{
        require(_whitelistedPolicies.contains(policy),"policy not in writelist");
        _whitelistedPolicies.remove(policy);
        emit PolicyRemoved(policy);
    }

    function isPolicyWhitelisted(address policy) external view override returns(bool){
        return _whitelistedPolicies.contains(policy);
    }

    function viewCountWhitelistedPolicies() external view override returns (uint256){
        return _whitelistedPolicies.length();
    }

    function viewWhitelistedPolicies (uint256 cursor,uint256 size) external view override returns(address[] memory,uint256){
        uint256 length = size;
        if(length > _whitelistedPolicies.length()-cursor){
            length = _whitelistedPolicies.length()-cursor;
        }

        address[] memory whitelistedPolicies = new address[](length);

        for(uint256 i=0;i<length;i++){
            whitelistedPolicies[i] = _whitelistedPolicies.at(cursor+i);
        }

        return (whitelistedPolicies,cursor+length);
    }
}
