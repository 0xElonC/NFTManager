import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades"; 
const config: HardhatUserConfig = {
  solidity: {
    version:"0.8.28",
    settings:{
      optimizer:{
        enabled:true,
        runs:10000,
      },
      viaIR:true
    }
  }
};
module.exports = {
  solidity: "0.8.28",
  networks: {
    sepolia: {
      url: "https://sepolia.infura.io/v3/d5d91cf71a454e7c8eda31706695c919", // 或者 alchemy rpc
      accounts: ["0x2cc0e8757bd16477d9ccc3dc676a2f1d625da1fcd62cdbf94b4503f9d8facd03"], // 部署钱包私钥
    },
  },
};
export default config;
