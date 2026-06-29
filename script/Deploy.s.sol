// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PrivacyBountyJudge.sol";

contract DeployPrivacyBountyJudge is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        PrivacyBountyJudge judge = new PrivacyBountyJudge();

        vm.stopBroadcast();

        console.log("PrivacyBountyJudge deployed at:", address(judge));
    }
}