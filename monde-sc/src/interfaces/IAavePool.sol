// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DataTypes} from "../librairies/DataTypes.sol";

interface IAavePool {

    function supply(
        bytes32 args
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    function getReserveData(address asset) external view returns (DataTypes.ReserveDataLegacy memory);
}
