pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/NftToken_Management/V2/NFTOrderManagerV2_2.sol";

contract RedeployV2_2AndUpgrade is Script {
    function run() external {
        address proxyAddress = 0x4c85004Ef5c4124E8acEf182700B4aec971974b1;
        uint256 deployerPrivateKey = 0x2cc0e8757bd16477d9ccc3dc676a2f1d625da1fcd62cdbf94b4503f9d8facd03;
        
        console.log("=== Redeploy V2_2 and Upgrade ===");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. 检查之前失败的地址
        address failedAddress = 0xcda62FdE3543CAb460aFc4485782aD504F3d4f6d;
        uint256 failedCodeSize;
        assembly {
            failedCodeSize := extcodesize(failedAddress)
        }
        console.log("Previous failed deployment address:", failedAddress);
        console.log("Previous deployment code size:", failedCodeSize);
        
        if (failedCodeSize == 0) {
            console.log(" Confirmed: Previous deployment has no code");
        }
        
        // 2. 重新部署 V2_2 实现合约
        console.log("Deploying fresh V2_2 implementation...");
        NFTOrderManagerV2_2 newImpl = new NFTOrderManagerV2_2();
        address newImplAddress = address(newImpl);
        console.log(" New V2_2 deployed at:", newImplAddress);
        
        // 3. 验证新部署确实有代码
        uint256 newCodeSize;
        assembly {
            newCodeSize := extcodesize(newImplAddress)
        }
        console.log("New implementation code size:", newCodeSize);
        require(newCodeSize > 0, "New deployment failed - no code");
        
        // 4. 验证新实现有必要的 UUPS 函数
        (bool hasProxiableUUID,) = newImplAddress.staticcall(
            abi.encodeWithSignature("proxiableUUID()")
        );
        console.log("New impl has proxiableUUID:", hasProxiableUUID);
        require(hasProxiableUUID, "New implementation missing UUPS functions");
        
        // 5. 记录升级前状态
        bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 beforeImplBytes = vm.load(proxyAddress, IMPLEMENTATION_SLOT);
        address beforeImpl = address(uint160(uint256(beforeImplBytes)));
        console.log("Before upgrade - Current implementation:", beforeImpl);
        
        // 6. 执行升级
        console.log("Executing upgradeToAndCall to new implementation...");
        
        (bool success, bytes memory data) = proxyAddress.call(
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImplAddress, "")
        );
        
        if (success) {
            console.log(" Upgrade transaction successful!");
            
            // 7. 验证升级结果
            bytes32 afterImplBytes = vm.load(proxyAddress, IMPLEMENTATION_SLOT);
            address afterImpl = address(uint160(uint256(afterImplBytes)));
            console.log("After upgrade - New implementation:", afterImpl);
            
            if (afterImpl == newImplAddress) {
                console.log(" UPGRADE SUCCESSFUL!");
                
                // 8. 测试新功能
                console.log("\n=== Testing V2_2 Functions ===");
                
                // 测试版本函数
                (bool versionSuccess, bytes memory versionData) = proxyAddress.staticcall(
                    abi.encodeWithSignature("getVersion()")
                );
                
                if (versionSuccess && versionData.length > 0) {
                    string memory version = abi.decode(versionData, (string));
                    console.log(" getVersion() works! Version:", version);
                } else {
                    console.log(" getVersion() failed");
                }
                
                // 测试 VERSION 常量
                (bool constantSuccess, bytes memory constantData) = proxyAddress.staticcall(
                    abi.encodeWithSignature("VERSION()")
                );
                
                if (constantSuccess && constantData.length > 0) {
                    string memory constantVersion = abi.decode(constantData, (string));
                    console.log(" VERSION constant works! Version:", constantVersion);
                } else {
                    console.log(" VERSION constant failed");
                }
                
                // 测试基础功能仍然工作
                (bool ownerSuccess, bytes memory ownerData) = proxyAddress.staticcall(
                    abi.encodeWithSignature("owner()")
                );
                
                if (ownerSuccess && ownerData.length >= 32) {
                    address owner = abi.decode(ownerData, (address));
                    console.log(" Basic functions work. Owner:", owner);
                }
                
                // 检查 executeV2 是否存在（不调用，只检查）
                (bool executeV2Exists,) = proxyAddress.staticcall(
                    abi.encodeWithSignature("executeV2((uint8,(uint8,uint8,address,uint256,uint256,address,uint256,uint256,uint256,bytes),uint8,uint256,uint8,bytes,uint256))")
                );
                console.log(" executeV2 function exists:", executeV2Exists);
                
            } else {
                console.log(" UPGRADE FAILED - Implementation slot not updated");
                console.log("Expected:", newImplAddress);
                console.log("Actual:", afterImpl);
            }
            
        } else {
            console.log(" Upgrade transaction failed:");
            console.logBytes(data);
        }
        
        vm.stopBroadcast();
    }
}