// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {VaulteraSmartAccount} from "src/vaulteraSmartAccount/VaulteraSmartAccount.sol";

contract DeployVaulteraSmartAccount is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address feeManager = 0xF77f34d881883054aa0478Ae71F91273f8D997B7;
        address entryPoint = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

        vm.startBroadcast(pk);
        VaulteraSmartAccount account = new VaulteraSmartAccount(feeManager, entryPoint);
        vm.stopBroadcast();

        console.log("VaulteraSmartAccount deployed:", address(account));
        console.log("FeeManager:", feeManager);
        console.log("EntryPoint:", entryPoint);
    }
}


