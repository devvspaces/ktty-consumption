// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {KttyWorldBooks} from "../src/KttyWorldBooks.sol";

contract UpgradeNFTRewardManagerScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("BOOKS_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new implementation
        KttyWorldBooks newImplementation = new KttyWorldBooks();
        console.log("New Books implementation deployed at:", address(newImplementation));

        // Upgrade the proxy
        KttyWorldBooks proxy = KttyWorldBooks(proxyAddress);
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

        console.log("Books proxy upgraded successfully");
        console.log("New implementation:", address(newImplementation));
    }
}