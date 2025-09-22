// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ETHPoolProxy is ERC1967Proxy {
    /**
     * @param logic 逻辑合约地址
     * @param data 初始化 calldata，例如 initialize(address)
     */
    constructor(address logic, bytes memory data) 
        ERC1967Proxy(logic, data) 
    {
        // ERC1967Proxy 会自动存储 implementation
        // admin 角色逻辑在 UUPSUpgradeable 中控制
    }
}
