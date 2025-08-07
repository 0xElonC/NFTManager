// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract NFTOrderProxy is TransparentUpgradeableProxy{
    constructor (
        address logic,
        address admin,
        bytes memory data
    ) TransparentUpgradeableProxy(logic,admin,data){}
}

contract NFTOrderProxyAdmin is ProxyAdmin{
    constructor (address initOwner) ProxyAdmin(initOwner){
        require(initOwner!=address(0),"Invail Owner");
    }
}