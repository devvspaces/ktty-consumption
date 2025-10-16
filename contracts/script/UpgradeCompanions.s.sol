// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {KttyWorldCompanions} from "../src/KttyWorldCompanions.sol";

contract UpgradeNFTRewardManagerScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("COMPANIONS_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new implementation
        KttyWorldCompanions newImplementation = new KttyWorldCompanions();
        console.log("New Companions implementation deployed at:", address(newImplementation));

        // Upgrade the proxy
        KttyWorldCompanions proxy = KttyWorldCompanions(proxyAddress);
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

        console.log("Companions proxy upgraded successfully");
        console.log("New implementation:", address(newImplementation));
    }
}