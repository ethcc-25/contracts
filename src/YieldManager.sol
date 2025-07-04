// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IAavePool} from "./interfaces/IAavePool.sol";
import {ITokenMessengerV2} from "./interfaces/ITokenMessengerV2.sol";
import {IMessageTransmitterV2} from "./interfaces/IMessageTransmitterV2.sol";
import {DataTypes} from "./librairies/DataTypes.sol";

contract YieldManager is AccessControl {

    using SafeCast for uint256;

    struct Position {
        uint8 pool; // 0 Aave - 1 Morpho - 2 Fluid
        bytes32 positionId; // unique identifier for the position
        address user;
        uint256 amountUsdc;
        uint256 amountAaveUsdc; // for Aave positions
    }

    ITokenMessengerV2     public immutable TOKEN_MESSENGER;
    IMessageTransmitterV2 public immutable MESSAGE_TRANSMITTER;
    IERC20                public immutable USDC;
    IERC20                public immutable AAVE_USDC;
    IAavePool             public immutable AAVE_POOL;

    address public operator;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(address => Position) public positions;

    event DepositProcessed(
        bytes32 indexed positionId,
        uint8 pool,
        address indexed user,
        uint256 amount
    );

    event WithdrawProcessed(
        bytes32 indexed positionId,
        uint8 pool,
        address indexed user,
        uint256 amount
    );

    constructor(
        address _tokenMessenger,
        address _messageTransmitter,
        address _aavePool,
        address _usdc,
        address _aaveUsdc
    ) {
        TOKEN_MESSENGER = ITokenMessengerV2(_tokenMessenger);
        MESSAGE_TRANSMITTER = IMessageTransmitterV2(_messageTransmitter);
        AAVE_POOL = IAavePool(_aavePool);
        USDC = IERC20(_usdc);
        AAVE_USDC = IERC20(_aaveUsdc);

        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    // =============================================================
    //                     OPERATOR FUNCTIONS
    // =============================================================

    function processDeposit(
        bytes memory _message,
        bytes memory _attestation
    ) external onlyRole(OPERATOR_ROLE) {
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(address(this));

        bool success = MESSAGE_TRANSMITTER.receiveMessage(
            _message,
            _attestation
        );

        require(success, "YieldManager: Message processing failed");

        (uint8 pool, address from, uint256 amount) = abi.decode(
            _message,
            (uint8, address, uint256)
        );

        require(amount == IERC20(USDC).balanceOf(address(this)) - usdcBalanceBefore, "YieldManager: Amount mismatch");

        uint256 amountAaveUsdc = 0;

        if (pool == 0) {
            amountAaveUsdc = _depositAave(amount);
        } else {
            revert("YieldManager: Invalid pool");
        }

        bytes32 positionId = keccak256(
            abi.encodePacked(pool, from, block.timestamp)
        );

        if (positions[from].user != address(0)) {
            positions[from].amountUsdc += amount;
        } else {
            Position storage newPosition = positions[from];
            newPosition.pool = pool;
            newPosition.positionId = positionId;
            newPosition.user = from;
            newPosition.amountUsdc = amount;
            newPosition.amountAaveUsdc = amountAaveUsdc;
        }

        emit DepositProcessed(positionId, pool, from, amount);
    }

    function processRebalancing(
        address user,
        uint8 destChainId,
        bytes memory message
    ) external onlyRole(OPERATOR_ROLE) {
        // This function will handle rebalancing logic
        // It will be called by the operator to rebalance positions across different pools
        // The logic will depend on the specific requirements of the rebalancing strategy
        // If the rebalancing is on the same chain, we can directly call the AavePool or Morpho contracts
    }

    function processWithdraw(
        bytes memory _message,
        bytes memory _attestation
    ) external onlyRole(OPERATOR_ROLE) {
        // when the withdraw is already initiated and USDC are bridged
        // we call MESSAGE_TRANSMITTER.receiveMessage(message, attestation);
        // We send it to the user

        bool success = MESSAGE_TRANSMITTER.receiveMessage(
            _message,
            _attestation
        );

        require(success, "YieldManager: Message processing failed");
    }

    function initWithdraw(
        address user
    ) external onlyRole(OPERATOR_ROLE) {
        // init withdraw from protocol
        // 
    }


    // =============================================================
    //                          INTERNALS
    // =============================================================

    function _depositAave(uint256 amount) internal returns (uint256) {

        uint256 aaveUsdcBalanceBefore = AAVE_USDC.balanceOf(address(this));
    
        IERC20(USDC).approve(address(AAVE_POOL), amount);
        AAVE_POOL.supply(encodeSupplyParams(address(USDC), amount, 0));

        return AAVE_USDC.balanceOf(address(this)) - aaveUsdcBalanceBefore;
    }


    // =============================================================
    //                          UTILS
    // =============================================================

    function encodeSupplyParams(
        address asset,
        uint256 amount,
        uint16 referralCode
    ) public view returns (bytes32) {
        DataTypes.ReserveDataLegacy memory data = AAVE_POOL.getReserveData(asset);

        uint16 assetId = data.id;
        uint128 shortenedAmount = amount.toUint128();
        bytes32 res;

        assembly {
            res := add(
                assetId,
                add(shl(16, shortenedAmount), shl(144, referralCode))
            )
        }
        return res;
    }
}
