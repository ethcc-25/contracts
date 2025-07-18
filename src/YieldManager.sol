


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
        uint8   pool;         // 1 Aave - 2 Morpho - 3 Fluid
        bytes32 positionId;   // unique identifier for the position
        address user;         // user address
        uint256 amountUsdc;   // amount of USDC deposited
        uint256 shares;       // ERC4626 shares
        address vault;
    }

    ITokenMessengerV2     public immutable TOKEN_MESSENGER;
    IMessageTransmitterV2 public immutable MESSAGE_TRANSMITTER;
    IERC20                public immutable USDC;
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

    constructor(
        address _tokenMessenger,
        address _messageTransmitter,
        address _usdc,
        bool    _isWorld
    ) {
        TOKEN_MESSENGER     = ITokenMessengerV2(_tokenMessenger);
        MESSAGE_TRANSMITTER = IMessageTransmitterV2(_messageTransmitter);
        USDC                = IERC20(_usdc);
        IS_WORLD            = _isWorld;

        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    // =============================================================
    //                     USERS FUNCTIONS
    // =============================================================

    /**
     * @notice Initiates a deposit from WORLD to a yield pool on a remote chain
     */
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

    /**
     * @notice Processes deposit from CCTP to yield pool
    */
    function processDeposit(
        bytes memory _message,
        bytes memory _attestation
    ) external onlyRole(OPERATOR_ROLE) {

        bool success = MESSAGE_TRANSMITTER.receiveMessage(_message, _attestation);
        require(success, "YieldManager: Message processing failed");

        (uint8 pool, address from, uint256 amount, address vault) = extractParams(_message);

        uint256 amountWithFee = (amount * (1e6 - CCTP_FEE)) / 1e6;
        uint256 shares = 0;

        bytes32 positionId = keccak256(abi.encodePacked(pool, from, block.timestamp));

        if      (pool == 1) shares = depositAave(amountWithFee, vault);
        else if (pool == 2) shares = depositMorpho(amountWithFee, vault);
        else revert("YieldManager: Invalid pool");

        Position storage position = positions[from];
        position.pool = pool;
        position.positionId = positionId;
        position.user = from;
        position.amountUsdc += amountWithFee;
        position.shares += shares;
        position.vault = vault;

        emit DepositProcessed(positionId, pool, from, amount, shares);
    }

    /**
     * @notice Processes a withdrawal from CCTP to user on WORLD
     */
    function processWithdraw(
        bytes memory _message,
        bytes memory _attestation
    ) external onlyRole(OPERATOR_ROLE) {
        bool success = MESSAGE_TRANSMITTER.receiveMessage(_message, _attestation);
        require(success, "YieldManager: Message processing failed");
    }

    /**
     * @notice Initializes the withdrawal process for a user from a remote chain to WORLD
     */
    function initWithdraw(address user) external onlyRole(OPERATOR_ROLE) {
        Position storage position = positions[user];
        require(
            position.user != address(0),
            "YieldManager: No position found for user"
        );

        uint256 withdrawnAmount = 0;

        if (position.pool == 1) {
            withdrawnAmount = withdrawAave(position);
            bridgeTo(withdrawnAmount, WORLD_DOMAIN, position);
        }
        else if (position.pool == 2) {
            withdrawnAmount = withdrawMorpho(position);
            bridgeTo(withdrawnAmount, WORLD_DOMAIN, position);
        }
        else {
            revert("YieldManager: Invalid pool");
        } 

        emit WithdrawProcessed(
            position.positionId,
            position.pool,
            user,
            withdrawnAmount
        );

        delete positions[user];
    }

    // =============================================================
    //                          VIEWS
    // =============================================================

    function getEarnedUSDCAave(
        address user
    ) public view returns (uint256) {
        Position memory position = positions[user];
        DataTypes.ReserveDataLegacy memory data = IAavePool(position.vault)
            .getReserveData(address(USDC));
        uint256 currentValue = (position.shares * uint256(data.liquidityIndex)) / 1e27;
        return currentValue > position.amountUsdc ? currentValue - position.amountUsdc : 0;
    }

    function getEarnedUSDCMorpho(
        address user
    ) public view returns (uint256) {
        Position memory position = positions[user];
        uint256 currentValue = IMorphoVault(position.vault).convertToAssets(position.shares);
        return currentValue > position.amountUsdc ? currentValue - position.amountUsdc : 0;
    }

    // =============================================================
    //                          DEPOSITS
    // =============================================================

    function depositAave(uint256 amount, address vault) internal returns (uint256) {

        DataTypes.ReserveDataLegacy memory dataBefore = IAavePool(vault).getReserveData(address(USDC));
        uint256 scaledBalanceBefore = (IERC20(dataBefore.aTokenAddress).balanceOf(address(this)) * 1e27) / dataBefore.liquidityIndex;
        
        IERC20(USDC).approve(address(vault), amount);

        DataTypes.ReserveDataLegacy memory data = IAavePool(vault).getReserveData(address(USDC));

        uint16 assetId = data.id;
        uint128 shortenedAmount = amount.toUint128();
        bytes32 res;

        assembly {
            res := add(
                assetId,
                add(shl(16, shortenedAmount), shl(144, 0))
            )
        }

        IAavePool(vault).supply(res);
        
        DataTypes.ReserveDataLegacy memory dataAfter = IAavePool(vault).getReserveData(address(USDC));
        uint256 scaledBalanceAfter = (IERC20(dataBefore.aTokenAddress).balanceOf(address(this)) * 1e27) / dataAfter.liquidityIndex;
        
        return scaledBalanceAfter - scaledBalanceBefore;
    }


    function depositMorpho(uint256 amount, address vault) internal returns (uint256) {

        IERC20(USDC).approve(vault, amount);
        uint256 shares = IMorphoVault(vault).deposit(amount, address(this));

        return shares;
    }

    // =============================================================
    //                          WITHDRAWALS
    // =============================================================

    function withdrawAave(Position memory position) internal returns (uint256) {
        DataTypes.ReserveDataLegacy memory data = IAavePool(position.vault).getReserveData(address(USDC));

        uint256 withdrawableAmount =  (position.shares * uint256(data.liquidityIndex)) / 1e27;
        require(withdrawableAmount > 0, "YieldManager: No withdrawable amount");

        uint256 withdrawnAmount = IAavePool(position.vault).withdraw(
            address(USDC),
            withdrawableAmount,
            address(this)
        );

        return withdrawnAmount;
    }

    function withdrawMorpho(Position memory position) internal returns (uint256) {

        uint256 withdrawnAmount = IMorphoVault(position.vault).redeem(
            position.shares,
            address(this),
            address(this)
        );

        return withdrawnAmount;
    }

    function bridgeTo(
        uint256 amount,
        uint32 destDomain,
        Position memory position
    ) internal {
        uint256 fee = (amount * CCTP_FEE) / 1e6;

        IERC20(USDC).approve(
            address(TOKEN_MESSENGER),
            amount
        );

        bytes memory message = abi.encode(
            position.user // user address
        );

        TOKEN_MESSENGER.depositForBurnWithHook(
            amount,
            destDomain,
            bytes32(uint256(uint160(position.user))),
            address(USDC),
            bytes32(0),
            fee,
            MIN_FINALITY_THRESHOLD,
            message
        );
    }

    // =============================================================
    //                          UTILS
    // =============================================================


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
}

