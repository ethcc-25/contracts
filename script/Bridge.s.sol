// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {ITokenMessengerV2} from "../src/interfaces/ITokenMessengerV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// BASE -> ARBITRUM (mainnet)
contract BridgeUSDC is Script {

    ITokenMessengerV2 public messenger = ITokenMessengerV2(0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d);
    IERC20 public usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913); // USDC on BASE
    uint8 public destinationChainId = 3; // ARB MAINNET

    address public morphoVault = 0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183;

    function run() external {
        uint256 pkey = vm.envUint("PKEY");
        address wallet = vm.addr(pkey);
        uint256 amount = 100000; // 0.1 USDC

        vm.startBroadcast(pkey);

        bytes memory data = abi.encode(
            uint8(1), // aave pool
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
            bytes32(uint256(uint160(0x260857AA3776B50363091839998B8Dd688C585d7))), // recipient address
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC address on BASE
            bytes32(0), // destination caller => allowed address to get the tokens on the destination chain
            99999, // max fee
            1000, // min finality threshold
            data
        );

        vm.stopBroadcast();

    }
}
