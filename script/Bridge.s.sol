// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {ITokenMessengerV2} from "../src/interfaces/ITokenMessengerV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// WORLD -> BASE (mainnet)
// forge script ./script/Bridge.s.sol --rpc-url https://worldchain-mainnet.g.alchemy.com/public --broadcast
contract BridgeUSDC is Script {

    ITokenMessengerV2 public messenger = ITokenMessengerV2(0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d);
    IERC20 public usdc = IERC20(0x79A02482A880bCE3F13e09Da970dC34db4CD24d1); // USDC on WORLD
    uint8 public destinationChainId = 6; // BASE MAINNET
    address public vault = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5; // AAVE vault on BASE
    address public morphoVault = 0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183; // Morpho vault on BASE

    function run() external {
        uint256 pkey = vm.envUint("PKEY");
        address wallet = vm.addr(pkey);
        uint256 amount = 100000; // 0.1 USDC

        vm.startBroadcast(pkey);

        bytes memory data = abi.encode(
            uint8(2), // morpho pool
            wallet, // user address
            amount, // amount to deposit
            morphoVault
        );

        usdc.approve(
            address(messenger), // USDC CCTP messenger address
            amount // amount to deposit
        );

        messenger.depositForBurnWithHook(
            amount, // amount to deposit
            destinationChainId, //
            bytes32(uint256(uint160(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f))), // recipient address
            0x79A02482A880bCE3F13e09Da970dC34db4CD24d1, // USDC address on WORLD
            bytes32(0), // destination caller => allowed address to get the tokens on the destination chain
            99999, // max fee
            1000, // min finality threshold
            data
        );

        vm.stopBroadcast();

    }
}
