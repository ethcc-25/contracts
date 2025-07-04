// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {ITokenMessengerV2} from "../src/interfaces/ITokenMessengerV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// OP -> BASE
contract BridgeUSDC is Script {

    ITokenMessengerV2 public messenger = ITokenMessengerV2(0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA);
    IERC20 public usdc = IERC20(0x5fd84259d66Cd46123540766Be93DFE6D43130D7); // USDC on OP Sepolia

    function run() external {
        uint256 pkey = vm.envUint("PKEY");
        address wallet = vm.addr(pkey);
        uint256 amount = 100000; // 0.1 USDC

        vm.startBroadcast(pkey);

        bytes memory data = abi.encode(
            uint8(1), // test pool
            wallet, 
            amount
        );

        usdc.approve(
            address(messenger),
            amount
        );

        messenger.depositForBurnWithHook(
            amount,
            6, // base sepolia
            bytes32(uint256(uint160(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f))), // recipient address
            0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC address on OP
            bytes32(0), // destination caller ? 
            99999, // max fee
            1000, // min finality threshold
            data
        );

        vm.stopBroadcast();

    }
}
