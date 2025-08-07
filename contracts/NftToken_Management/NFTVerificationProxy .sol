// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title NFTVerificationProxy
 * @author
 * @notice NFT management proxy
 */
contract NFTVerificationProxy is TransparentUpgradeableProxy {
    constructor(
        address logic,
        address admin,
        bytes memory data
    ) TransparentUpgradeableProxy(logic, admin, data) {}
}

/**
 * @title NFTVerificationProxyAdmin
 * @author
 * @notice
 */
contract NFTVerificationProxyAdmin is ProxyAdmin {
    constructor(address initialOwner) ProxyAdmin(initialOwner) {
        require(initialOwner != address(0), "Invail Owner");
    }
}
