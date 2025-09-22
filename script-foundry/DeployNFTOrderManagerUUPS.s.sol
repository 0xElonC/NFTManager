pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {ETHPool} from "../contracts/pool/ETHPool.sol";
import {ETHPoolProxy} from "../contracts/pool/proxy/ETHPoolProxy.sol";
import {NFTOrderManager} from "../contracts/NftToken_Management/NFTOrderManager.sol";
import {NFTOrderProxy} from "../contracts/NftToken_Management/NFTOrderProxy.sol";
import {PolicyManager} from "../contracts/NftToken_Management/policyManage/PolicyManager.sol";
import {ExecutionDelegate} from "../contracts/NftToken_Management/ExecutionDelegate.sol";

contract DeployNFTOrderManagerUUPS is Script {
    function run() external {
        //配置参数
        address owner = 0xF3100E0aa3a409e80d6dfbDcCc092DE3000347c9;
        address[] memory initialPolicies = new address[](0);//初始化白名单策略
        address PolicyManager;
        address ExecutionDelegate;

        vm.startBroadcast();

        //部署policyManager 0xd8D3dFd4ee0EC28214210fA2F8cEc9166c53B0E8
        // PolicyManager pm = new PolicyManager(owner,initialPolicies);
        // policyManager = address(pm);
        // console.log("PolicyManager:", policyManager);
        PolicyManager = 0xd8D3dFd4ee0EC28214210fA2F8cEc9166c53B0E8;
        //部署ExecutionDelegate 0x8c35EbA1A0543737626425abC778368D82902E24
        //ExecutionDelegate ed = new ExecutionDelegate(owner);
        //executionDelegate = address(ed);
        //console.log("ExecutionDelegate:", executionDelegate);
        ExecutionDelegate = 0x8c35EbA1A0543737626425abC778368D82902E24;

        //部署POOL实现合约
        ETHPool poolimpl = new ETHPool();
        console.log("ETHPool implementation:", address(poolimpl));

        //构造POOL的初始化数据
        bytes memory initPoolData = abi.encodeWithSignature(
            "initialize(address)",
             owner
        );
        //部署POOL的 proxy合约
        ETHPoolProxy poolProxy = new ETHPoolProxy(
            address(poolimpl),
            initPoolData
        );
        console.log("ETHpool UUPS Proxy:", address(poolProxy));


        //部署NFTOrderManagers实现
        NFTOrderManager impl = new NFTOrderManager();
        console.log("NFTOrderManager implementation:", address(impl));

        //构造初始化数据
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address)", 
            owner,
            PolicyManager,
            ExecutionDelegate,
            address(poolProxy)
        );
        //部署uups代理
        NFTOrderProxy proxy = new NFTOrderProxy(
            address(impl),
            initData
        );
        console.log("NFTOrderManager UUPS Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}