# NFT 智能合约系统

本项目是一个基于 Solidity 的 NFT 交易撮合与资金托管平台，采用 UUPS 可升级架构，包含订单管理、策略白名单、执行委托和 ETH 资金池模块。适用于二级市场 NFT 交易等场景。

- 升级模式：OpenZeppelin UUPS (v5)
- 工具链：Foundry（forge/cast/anvil）
- 链：兼容 EVM 的公链/测试网

---

## 目录结构

```
contracts/
  NftToken_Management/
    NFTOrderManager.sol            # 主订单撮合合约（UUPS，可升级）
    NFTOrderProxy.sol              # 订单管理代理（ERC1967Proxy 包装）
    ExecutionDelegate.sol          # 执行委托（NFT/ERC20/ERC1155 安全转移）
    interfaces/
      IExecutionDelegate.sol
      INFTOrderManager.sol
    policyManage/
      PolicyManager.sol            # 策略白名单管理（Ownable）
      interfaces/
        IMatchingPolicy.sol
        IPolicyManager.sol
      matchingPolices/
        SafeCollectionBidPolicyERC721.sol
        StandardPolicyERC721.sol
        StandardPolicyERC721_1.sol
    struct/
      OrderStruct.sol              # 订单结构体定义
    utils/
      MerkleVerifier.sol           # Merkle 白名单校验
      OrderEIP712.sol              # EIP-712 域与签名
  pool/
    ETHPool.sol                    # ETH 资金池（UUPS，可升级）
    interfaces/
      IETHPool.sol
    proxy/
      ETHPoolProxy.sol             # 资金池代理（ERC1967Proxy 包装）
TestERC721.sol                     # 测试用 ERC721
```

---

## 模块说明

### 1) NFTOrderManager（订单管理）
- 初始化函数
  - initialize(address ownerAddress, IPolicyManager _policyManager, IExecutionDelegate _executionDelegate, address _pool)
  - 设置所有权、策略管理、执行委托与资金池地址
- 状态变量与能力
  - address public POOL：资金池代理地址
  - IPolicyManager public policyManager
  - IExecutionDelegate public executionDelegate
  - EIP-712 域、订单计数、可批量撮合、可暂停
- 升级安全
  - 继承 UUPSUpgradeable，_authorizeUpgrade 由 onlyOwner 控制

### 2) ETHPool（资金池）
- 初始化函数
  - initialize(address ownerAddress)
- 关键方法
  - updateEXCHANGE(address _exchange) onlyOwner：设置可调用受限转账的 EXCHANGE（应为 NFTOrderManager 代理地址）
- 升级安全
  - UUPSUpgradeable + onlyOwner

### 3) PolicyManager（策略白名单）
- 管理可用撮合策略，支持增删查
- Ownable 控制，便于风控

### 4) ExecutionDelegate（执行委托）
- 统一处理 NFT/ERC20/ERC1155 的安全转移
- 与订单撮合解耦

---

## 环境准备

- 安装 Foundry
  - Windows（PowerShell）：`iwr https://foundry.paradigm.xyz | Invoke-Expression`
  - 初始化：`foundryup`
- Node（可选，用于脚手架/周边）：https://nodejs.org/

建议创建 .env（不提交到仓库）：
```
RPC_URL=<your_rpc_url>
PRIVATE_KEY=<your_deployer_private_key>
```

---

## 编译与测试

```bash
forge build
forge test
forge fmt
anvil  # 启动本地链（可选）
```

---

## 部署与初始化（UUPS）

注意：OpenZeppelin v5 UUPS 只提供 upgradeToAndCall(address,bytes)。初始化必须通过代理构造函数的 data 参数进行 delegatecall。

以下为推荐顺序：

1) 部署 ETHPool 实现与代理（初始化 owner）
2) 部署 PolicyManager 与 ExecutionDelegate
3) 部署 NFTOrderManager 实现与代理（初始化 owner、policyManager、executionDelegate、pool）
4) 用 owner 调用 ETHPool.updateEXCHANGE，将 EXCHANGE 指向 NFTOrderManager 代理

如你已准备好 Foundry 脚本，可直接执行：
```bash
forge script script-foundry/DeployNFTOrderManagerUUPS.s.sol \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key> \
  --broadcast
```

如果手动调用（示例，使用 cast 拼装 data）：

- 资金池代理部署（ERC1967Proxy 构造：logic, data）
  - data = abi.encodeWithSignature("initialize(address)", owner)
- 订单管理代理部署（ERC1967Proxy 构造：logic, data）
  - data = abi.encodeWithSignature(
      "initialize(address,address,address,address)",
      owner, policyManager, executionDelegate, poolProxy
    )

---

## 升级流程（UUPS）

1) 部署新实现合约（不可直接调用 initialize）
2) 通过代理调用 upgradeToAndCall(newImpl, 0x)

cast 示例：
```bash
# 查看实现槽（ERC1967 implementation slot）
cast storage <Proxy> 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url <RPC_URL>

# 升级（使用 owner 私钥）
cast send <Proxy> "upgradeToAndCall(address,bytes)" <NewImplementation> 0x \
  --rpc-url <RPC_URL> \
  --private-key <OWNER_PRIVATE_KEY>

# 再次查看实现槽确认
cast storage <Proxy> 0x3608...bbc --rpc-url <RPC_URL>
```

---

## 常用链上检查

- 所有者（Owner）
```bash
cast call <Proxy> "owner()" --rpc-url <RPC_URL>
```

- 订单管理合约的资金池地址
```bash
cast call <NFTOrderManagerProxy> "POOL()" --rpc-url <RPC_URL>
```

- 设置资金池 EXCHANGE（需 owner）
```bash
cast send <ETHPoolProxy> "updateEXCHANGE(address)" <NFTOrderManagerProxy> \
  --rpc-url <RPC_URL> \
  --private-key <OWNER_PRIVATE_KEY>
```

- 合约代码存在性
```bash
cast code <Address> --rpc-url <RPC_URL>
```

- 版本信息（若实现了）
```bash
cast call <Proxy> "getVersion()" --rpc-url <RPC_URL>
# 或
cast call <Proxy> "VERSION()" --rpc-url <RPC_URL>
```

---

## 常见问题排查

- POOL 为 0
  - 确认 NFTOrderManager.initialize 内部包含 POOL = _pool;
  - 初始化严格通过代理 data 委托调用；不要直接对实现合约调用 initialize
  - data 函数签名与参数顺序、类型必须完全匹配

- 升级后功能不变/报错
  - 确认使用的是 upgradeToAndCall（v5 不再有 upgradeTo）
  - 新实现合约未初始化，且包含 UUPS 必要接口（proxiableUUID）
  - 检查实现槽是否已更新为新地址

- 权限失败（onlyOwner）
  - 用 cast 查询 owner()，确认私钥是否与 owner 一致
  - 通过代理地址调用，不要对实现地址调用

- 代理/实现地址混淆
  - 读写业务函数总是对“代理地址”
  - 升级/读取实现槽时才涉及实现地址

---

## 脚本与产物

- 部署与升级脚本建议放在 script-foundry/
  - DeployNFTOrderManagerUUPS.s.sol
  - NFTOrderManagerV2.s.sol（升级脚本/检查脚本）
- Foundry 广播产物默认在 broadcast/ 下
  - 建议将 broadcast/ 加入 .gitignore，避免将交易模拟/广播产物提交到仓库

.gitignore 示例：
```
node_modules/
broadcast/
cache/
artifacts/
.env*
Thumbs.db
coverage/
```

---

## 安全建议

- 升级逻辑仅由 owner 控制，谨慎保管私钥
- 新实现合约上链前应完整测试，避免初始化被意外调用
- 对关键地址（POOL、EXCHANGE、policyManager、executionDelegate）变更需审慎

---

## 许可证

本项目默认采用 MIT 许可证（如需变更请在仓库根目录添加 LICENSE）。

---

## 参考

- Foundry: https://book.getfoundry.sh/
- OpenZeppelin UUPS（v5）: https://docs.openzeppelin.com/contracts/5.x/upgradeable