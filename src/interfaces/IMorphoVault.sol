// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMorphoVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256);
}


