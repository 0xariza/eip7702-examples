// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {FeeManager} from "src/feeManager/FeeManager.sol";

contract DeployFeeManager is Script {

  
    address public TREASURY = 0x868984251192867D6E2BbD2d1E8DdE842B33dDd6;
    address public FEE_SIGNER = 0xaE87F9BD09895f1aA21c5023b61EcD85Eba515D1;
    uint256 public SYSTEM_FEE_BPS = uint256(50); // 0.5%
    uint256 public MAX_FEE_BPS = uint256(1000);     // 10%
    

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer:", deployer);
        console.log("Treasury:", TREASURY);
        console.log("Fee Signer:", FEE_SIGNER);
        console.log("System Fee (bps):", SYSTEM_FEE_BPS);
        console.log("Max Fee (bps):", MAX_FEE_BPS);
        

        vm.startBroadcast(pk);
        FeeManager feeManager = new FeeManager(
            TREASURY,
            SYSTEM_FEE_BPS,
            MAX_FEE_BPS,
            FEE_SIGNER,
            deployer
        );
        vm.stopBroadcast();

        console.log("FeeManager deployed:", address(feeManager));
    }
}


