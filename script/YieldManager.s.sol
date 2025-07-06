// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {YieldManager} from "../src/YieldManager.sol";

// forge script ./script/YieldManager.s.sol --rpc-url https://worldchain-mainnet.g.alchemy.com/public --broadcast
// forge script ./script/YieldManager.s.sol --rpc-url https://mainnet.optimism.io --broadcast
// 

contract Deploy is Script {

    YieldManager manager;
    address operator;

    function run() external {

        uint256 pkey = vm.envUint("OPERATOR_PKEY");
        operator = vm.addr(pkey);
        vm.startBroadcast(pkey);
        // BASE
        manager = new YieldManager(
            0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d,
            0x81D40F21F12A8F0E3252Bccb954D722d4c464B64,
            0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
            false 
        );

        console.log("YieldManager deployed at: %s", address(manager));

        vm.stopBroadcast();
    }
}