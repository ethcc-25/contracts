// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {YieldManager} from "../src/YieldManager.sol";

// forge script ./script/YieldManager.s.s.sol --rpc-url https://arbitrum.drpc.org --broadcast

contract Deploy is Script {

    YieldManager manager;
    address operator;

    function run() external {

        uint256 pkey = vm.envUint("PKEY");
        operator = vm.addr(pkey);
        vm.startBroadcast(pkey);

        manager = new YieldManager(
            0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d,
            0x81D40F21F12A8F0E3252Bccb954D722d4c464B64,
            0x794a61358D6845594F94dc1DB02A252b5b4814aD,
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            0x724dc807b04555b71ed48a6896b6F41593b8C637,
            true 
        );

        console.log("YieldManager deployed at: %s", address(manager));

        vm.stopBroadcast();
    }
}