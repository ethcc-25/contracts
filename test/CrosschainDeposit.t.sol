// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {YieldManager} from "../src/YieldManager.sol";

contract CrosschainDeposit is Test {

    YieldManager public yieldManager;
    address      public user = 0x31d2Af4c13737C89353710C4c2267E7217Bd6Aa8;
    address      public operator;

    function setUp() public {
        uint256 forkId = vm.createFork("https://arbitrum.drpc.org");
        vm.selectFork(forkId);

        operator = vm.addr(1);

        vm.deal(operator, 100 ether);
        vm.deal(user, 100 ether);

        yieldManager = new YieldManager(
            0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d, // Token Messenger 
            0x81D40F21F12A8F0E3252Bccb954D722d4c464B64, // Message Transmitter
            0x794a61358D6845594F94dc1DB02A252b5b4814aD, // Aave Pool
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831, // USDC address
            0x724dc807b04555b71ed48a6896b6F41593b8C637 //  Aave USDC address
        );
    }

    function test_deploy() public {
        console.log("YieldManager deployed at: %s", address(yieldManager));
    }

    function test_process_deposit() public {
        bytes memory attestion = hex"8fcade248afd1b5a04f5678420f6dd70dfd40a260bd6aa6c7079b0e8773131460fde68774596e6ced499444b1bf77dad6fb97920f169996072f875636bf267ca1c4d76873541c36caf168fab8d4887dbda4b501d9d8427ef307a50adf26fe19a904b867c07d261b3e536cd4b530a4d477d188151542e8aa8eb5cc22f2cd90e14731c";
        bytes memory message = hex"00000001000000060000000361c6c083cc1312521e3f78338424ef2dba6a40986d49db3242b1a8e2f85d6e2600000000000000000000000028b5a0e9c621a5badaa536219b3a228c8168cf5d00000000000000000000000028b5a0e9c621a5badaa536219b3a228c8168cf5d0000000000000000000000000000000000000000000000000000000000000000000003e8000003e800000001000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda029130000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000000186a000000000000000000000000031d2af4c13737c89353710c4c2267e7217bd6aa8000000000000000000000000000000000000000000000000000000000001869f000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000015ccfb3000000000000000000000000000000000000000000000000000000000000000100000000000000000000000031d2af4c13737c89353710c4c2267e7217bd6aa800000000000000000000000000000000000000000000000000000000000186a00000000000000000000000000000000000000000000000000000000000000000";

        yieldManager.processDeposit(
            message,
            attestion
        );
    }

    function test_init_withdraw() public {
        test_process_deposit();

        yieldManager.initWithdraw(
            address(user)
        );
    }
}
