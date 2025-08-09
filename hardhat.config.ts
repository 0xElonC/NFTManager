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

export default config;
