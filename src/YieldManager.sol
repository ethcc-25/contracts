


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ISignatureTransfer} from "./interfaces/ISignatureTransfer.sol";
import {IMorphoVault} from "./interfaces/IMorphoVault.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {ITokenMessengerV2} from "./interfaces/ITokenMessengerV2.sol";
import {IMessageTransmitterV2} from "./interfaces/IMessageTransmitterV2.sol";
import {DataTypes} from "./librairies/DataTypes.sol";

contract YieldManager is AccessControl, ReentrancyGuard {
    using SafeCast for uint256;

    struct Position {
        uint8 pool; // 1 Aave - 2 Morpho - 3 Fluid
        bytes32 positionId; // unique identifier for the position
        address user;
        uint256 amountUsdc;
        uint256 shares; // ERC4626 shares
    }

    ITokenMessengerV2     public immutable TOKEN_MESSENGER;
    IMessageTransmitterV2 public immutable MESSAGE_TRANSMITTER;
    IERC20                public immutable USDC;
    IERC20                public immutable AAVE_USDC;
    IAavePool             public immutable AAVE_POOL;
    ISignatureTransfer    public immutable PERMIT_2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    uint8   public WORLD_DOMAIN = 14;
    bool    public IS_WORLD = false;
    uint256 public CCTP_FEE = 100; // 0.01% 
    uint32  public MIN_FINALITY_THRESHOLD = 1000;

    address public operator;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(address => Position) public positions;

    event DepositInitiated(
        uint8 indexed pool,
        address indexed user,
        uint256 amount
    );

    event DepositProcessed(
        bytes32 indexed positionId,
        uint8 pool,
        address indexed user,
        uint256 amount,
        uint256 shares
    );

    event WithdrawProcessed(
        bytes32 indexed positionId,
        uint8 pool,
        address indexed user,
        uint256 amount
    );

    event YES(
        bool isWorld
    );

    constructor(
        address _tokenMessenger,
        address _messageTransmitter,
        address _aavePool,
        address _usdc,
        address _aaveUsdc,
        bool    _isWorld
    ) {
        TOKEN_MESSENGER     = ITokenMessengerV2(_tokenMessenger);
        MESSAGE_TRANSMITTER = IMessageTransmitterV2(_messageTransmitter);
        AAVE_POOL           = IAavePool(_aavePool);
        USDC                = IERC20(_usdc);
        AAVE_USDC           = IERC20(_aaveUsdc);
        IS_WORLD            = _isWorld;

        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    // =============================================================
    //                     USERS FUNCTIONS
    // =============================================================

    function signatureTransfer(
        uint8   pool,
        uint32  chaindId,
        address yieldManager,
        address vault,
        ISignatureTransfer.PermitTransferFrom memory permitTransferFrom,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        bytes calldata signature
    ) public {
        require(IS_WORLD, "YieldManager: Not on World chain");

        PERMIT_2.permitTransferFrom(
            permitTransferFrom,
            transferDetails,
            msg.sender,
            signature
        );

        USDC.approve(
            address(TOKEN_MESSENGER),
            transferDetails.requestedAmount
        );

        uint256 fee = (transferDetails.requestedAmount * CCTP_FEE) / 1e6;

        bytes memory message =  abi.encode(
            pool, // pool type 
            msg.sender, // user address
            transferDetails.requestedAmount, // amount to deposit
            vault // vault address if needed
        );

        TOKEN_MESSENGER.depositForBurnWithHook(
            transferDetails.requestedAmount, // amount to deposit
            chaindId, // destination chain ID
            bytes32(uint256(uint160(yieldManager))), // recipient address on the destination chain
            address(USDC), // USDC address on the source chain
            bytes32(0), // morpho vault address on the destination chain
            fee, // max fee for the CCTP transfer
            MIN_FINALITY_THRESHOLD, // min finality threshold
            message
        );

        emit DepositInitiated(
            pool,
            msg.sender,
            transferDetails.requestedAmount
        );
        
    }

    // =============================================================
    //                     OPERATOR FUNCTIONS
    // =============================================================

    function processDeposit(
        bytes memory _message,
        bytes memory _attestation
    ) external onlyRole(OPERATOR_ROLE) {
        bool success = MESSAGE_TRANSMITTER.receiveMessage(
            _message,
            _attestation
        );

        require(success, "YieldManager: Message processing failed");

        (
            uint8   pool,
            address from,
            uint256 amount,
            address morphoVault
        ) = extractParams(_message);

        // 0.01% CCTP fee
        uint256 amountWithFee = (amount * (1e6 - CCTP_FEE)) / 1e6;
        uint256 shares = 0;

        bytes32 positionId = keccak256(
            abi.encodePacked(pool, from, block.timestamp)
        );

        if (pool == 1) {
            shares = depositAave(amountWithFee);
        }
        else if (pool == 2){
            require(morphoVault != address(0), "YieldManager: Invalid morpho vault");
            shares = IMorphoVault(morphoVault).deposit(amountWithFee, from);
        }
         else {
            revert("YieldManager: Invalid pool");
        }

        if (positions[from].user != address(0)) {
            positions[from].amountUsdc += amountWithFee;
            positions[from].shares += shares;
        } else {
            Position storage newPosition = positions[from];
            newPosition.pool = pool;
            newPosition.positionId = positionId;
            newPosition.user = from;
            newPosition.amountUsdc = amountWithFee;
            newPosition.shares = shares;
        }

        emit DepositProcessed(positionId, pool, from, amount, shares);
    }

    function processRebalancing(
        address user,
        uint8 destChainId,
        bytes memory message
    ) external onlyRole(OPERATOR_ROLE) {}

    function processWithdraw(
        bytes memory _message,
        bytes memory _attestation
    ) external onlyRole(OPERATOR_ROLE) {
        // Used on World to process the withdrawal message
        // Take fees now

        bool success = MESSAGE_TRANSMITTER.receiveMessage(
            _message,
            _attestation
        );

        require(success, "YieldManager: Message processing failed");
    }

    function initWithdraw(address user) external onlyRole(OPERATOR_ROLE) {
        Position storage position = positions[user];
        require(
            position.user != address(0),
            "YieldManager: No position found for user"
        );

        uint256 withdrawnAmount = 0;

        if (position.pool == 1) {
            withdrawnAmount = withdrawAave(position);
        }
        else if (position.pool == 2) {

        } 

        emit WithdrawProcessed(
            position.positionId,
            position.pool,
            user,
            withdrawnAmount
        );

        // Reset the position
        delete positions[user];
    }

    // =============================================================
    //                          VIEWS
    // =============================================================

    function getWithdrawableUSDC(
        Position memory position
    ) public view returns (uint256) {
        DataTypes.ReserveDataLegacy memory data = IAavePool(AAVE_POOL)
            .getReserveData(address(USDC));
        return (position.shares * uint256(data.liquidityIndex)) / 1e27;
    }

    // =============================================================
    //                          INTERNALS
    // =============================================================

    function depositAave(uint256 amount) internal returns (uint256) {
        // Balance scaled AVANT le dépôt
        DataTypes.ReserveDataLegacy memory dataBefore = AAVE_POOL.getReserveData(address(USDC));
        uint256 scaledBalanceBefore = (IERC20(AAVE_USDC).balanceOf(address(this)) * 1e27) / dataBefore.liquidityIndex;
        
        // Effectuer le dépôt
        IERC20(USDC).approve(address(AAVE_POOL), amount);
        AAVE_POOL.supply(encodeSupplyParams(address(USDC), amount, 0));
        
        // Balance scaled APRÈS le dépôt (avec le nouvel index)
        DataTypes.ReserveDataLegacy memory dataAfter = AAVE_POOL.getReserveData(address(USDC));
        uint256 scaledBalanceAfter = (IERC20(AAVE_USDC).balanceOf(address(this)) * 1e27) / dataAfter.liquidityIndex;
        
        return scaledBalanceAfter - scaledBalanceBefore;
    }

    function withdrawAave(
        Position memory position
    ) internal returns (uint256) {

        uint256 withdrawableAmount = getWithdrawableUSDC(position);

        require(withdrawableAmount > 0, "YieldManager: No withdrawable amount");

        uint256 withdrawnAmount = AAVE_POOL.withdraw(
            address(USDC),
            withdrawableAmount,
            address(this)
        );

        require(
            withdrawnAmount == withdrawableAmount,
            "YieldManager: Withdrawn amount mismatch"
        );

        uint256 fee = (withdrawnAmount * CCTP_FEE) / 1e6;

        IERC20(USDC).approve(
            address(TOKEN_MESSENGER),
            withdrawnAmount
        );

        TOKEN_MESSENGER.depositForBurn(
            withdrawnAmount,
            WORLD_DOMAIN,
            bytes32(uint256(uint160(position.user))),
            address(USDC),
            bytes32(0),
            fee,
            MIN_FINALITY_THRESHOLD
        );

        return withdrawnAmount;
    }

    // =============================================================
    //                          UTILS
    // =============================================================

    function encodeSupplyParams(
        address asset,
        uint256 amount,
        uint16 referralCode
    ) public view returns (bytes32) {
        DataTypes.ReserveDataLegacy memory data = AAVE_POOL.getReserveData(
            asset
        );

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

    function extractParams(
        bytes memory data
    )
        public
        pure
        returns (uint8 pool, address from, uint256 amount, address vault)
    {
        require(data.length >= 128, "Data too short"); // 32 * 4 minimum

        assembly {
            let dataPtr := add(data, 32)
            let endPtr := add(dataPtr, sub(mload(data), 128))

            pool := byte(31, mload(add(endPtr, 0))) // uint8 
            from := mload(add(endPtr, 32)) // address 
            amount := mload(add(endPtr, 64)) // uint256
            vault := mload(add(endPtr, 96)) // address 
        }
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        IERC20(token).transfer(to, amount);
    }
}

