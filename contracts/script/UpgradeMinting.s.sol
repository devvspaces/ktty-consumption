// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {KttyWorldMinting} from "../src/KttyWorldMinting.sol";

contract UpgradeNFTRewardManagerScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("MINTING_CONTRACT_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new implementation
        KttyWorldMinting newImplementation = new KttyWorldMinting();
        console.log("New KttyWorldMinting implementation deployed at:", address(newImplementation));
        
        // Upgrade the proxy
        KttyWorldMinting proxy = KttyWorldMinting(proxyAddress);
        try proxy.upgradeToAndCall(address(newImplementation), "") {
            console.log("Upgrade successful!");
        } catch Error(string memory reason) {
            console.log("Upgrade failed with reason:", reason);
            revert(reason);
        } catch {
            console.log("Upgrade failed with low-level error");
            revert("Low-level upgrade error");
        }
        
        vm.stopBroadcast();

        console.log("KttyWorldMinting proxy upgraded successfully");
        console.log("New implementation:", address(newImplementation));
    }
}