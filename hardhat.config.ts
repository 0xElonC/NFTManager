import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades"; 

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10000, // 高 runs 值适合生产环境，优化长期调用成本
      },
      viaIR: true // 启用 IR 编译，解决栈溢出问题
    }
  },
  networks: {
    sepolia: {
      url: "https://sepolia.infura.io/v3/d5d91cf71a454e7c8eda31706695c919", // Infura Sepolia 节点
      accounts: ["0x2cc0e8757bd16477d9ccc3dc676a2f1d625da1fcd62cdbf94b4503f9d8facd03"], // 私钥（注意：生产环境不要硬编码私钥）
    }
  }
};

export default config;
