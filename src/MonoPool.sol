// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { Pool } from "./libs/PoolLib.sol";
import { Accounter } from "./libs/AccounterLib.sol";
import { BPS } from "./libs/SwapLib.sol";
import { Ops } from "./Ops.sol";

import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";
import { DecoderLib } from "./encoder/DecoderLib.sol";

/// @title MonoPool
/// @notice Same as the original MegaTokenPool, but with a single ERC_20 base token (useful for project that want a pool
/// for their internal swap)
/// @author KONFeature <https://github.com/KONFeature>
/// @author Inspired from (https://github.com/Philogy/singleton-swapper/blob/main/src/MegaPool.sol) by Phylogy
contract MonoPool is ReentrancyGuard {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;
    using DecoderLib for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                 Constant's                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev The max swap fee (5%)
    uint256 private constant MAX_SWAP_FEE = 50;

    /// @dev The min thresholds for the liqidity
    uint256 private constant MIN_LIQUIDITY_THRESHOLDS = 1000 ether;

    /// @dev The max thresholds for the liqidity
    uint256 private constant MAX_LIQUIDITY_THRESHOLDS = 1_000_000 ether;

    /// @dev The min dynamic bps fees (0.2%)
    uint256 private constant MIN_BPS = 2;

    /// @dev The max dynamic bps fees (1%)
    uint256 private constant MAX_BPS = 10;

    /**
     * @dev The token state to handle reserves & protocol fees
     */
    struct TokenState {
        uint256 totalReserves;
        uint256 protocolFees;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Storage                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev The fee that will be taken from each swaps
    uint256 private immutable FEE_BPS;

    /// @dev The token's we will use for the pool
    address private immutable TOKEN_0;
    address private immutable TOKEN_1;

    /// @dev The fee that will be taken from each swaps
    uint16 private swapFeePerThousands;

    /// @dev The receiver for the swap fees
    address private feeReceiver;

    /// @dev The mapping of all the pools per target token
    Pool private pool;

    /// @dev The current token state's
    TokenState private token0State;
    TokenState private token1State;

    /* -------------------------------------------------------------------------- */
    /*                               Custom error's                               */
    /* -------------------------------------------------------------------------- */

    error InvalidOp(uint256 op);
    error LeftOverDelta();
    error InvalidGive();
    error NegativeAmount();
    error NegativeReceive();
    error AmountOutsideBounds();
    error NotCurrentFeeReceiver();

    /* -------------------------------------------------------------------------- */
    /*                                 Constructor                                */
    /* -------------------------------------------------------------------------- */

    constructor(address token0, address token1, uint256 feeBps, address _feeReceiver, uint16 _swapFeePerThousands) {
        require(feeBps < BPS);
        require(token0 != address(0));
        require(token1 != address(0));
        require(_feeReceiver != address(0));
        require(_swapFeePerThousands <= MAX_SWAP_FEE);

        // Save base pool info's
        FEE_BPS = feeBps;
        TOKEN_0 = token0;
        TOKEN_1 = token1;

        // Save info's about protocol receiver
        feeReceiver = _feeReceiver;
        swapFeePerThousands = _swapFeePerThousands;
    }

    /* -------------------------------------------------------------------------- */
    /*                           External write method's                          */
    /* -------------------------------------------------------------------------- */

    /// @notice Update the fee receiver and the fee amount
    /// @dev Only the current fee receiver can update the fee receiver and the amount
    /// @param _feeReceiver The new fee receiver
    /// @param _swapFeePerThousands The new fee amount per thousand
    function updateFeeReceiver(address _feeReceiver, uint16 _swapFeePerThousands) external {
        if (feeReceiver != msg.sender) revert NotCurrentFeeReceiver();

        require(_swapFeePerThousands <= MAX_SWAP_FEE);

        if (_feeReceiver == address(0)) {
            require(_swapFeePerThousands == 0);
        }

        feeReceiver = _feeReceiver;
        swapFeePerThousands = _swapFeePerThousands;
    }

    /**
     * @notice Execute a program of operations on pools. The `program` is a serialized list of operations, encoded in a
     * specific format.
     * @dev This function uses a non-ABI encoding to ensure a custom set of operations, each taking on a different
     * amount of data while keeping calldata size minimal. It is not reentrant.
     * @param program Serialized list of operations, with each operation consisting of an 8-bit operation specifier and
     * parameters. The structure is as follows:
     *  2 bytes: accounting hash map size (in tokens) e.g. 0x0040 => up to 64 key, value pairs in the accounting map
     *  For every operation:
     *    1 byte:  8-bit operation (4-bits operation id and 4-bits flags)
     *    n bytes: opcode data
     * Refer to the function documentation for details on individual operations.
     */
    function execute(bytes calldata program) external payable nonReentrant {
        (uint256 ptr, uint256 endPtr) = _getPc(program);

        // Initialize the accounter
        Accounter memory accounter;
        {
            uint256 hashMapSize;
            (ptr, hashMapSize) = ptr.readUint(2);
            accounter.init(hashMapSize);
        }

        // Interpret each operations
        uint256 op;
        while (ptr < endPtr) {
            unchecked {
                (ptr, op) = ptr.readUint(1);
                ptr = _interpretOp(accounter, ptr, op);
            }
        }

        // If there are any leftover deltas, revert
        if (accounter.totalNonZero != 0) revert LeftOverDelta();
    }

    /* -------------------------------------------------------------------------- */
    /*                           Internal write method's                          */
    /* -------------------------------------------------------------------------- */

    /// @notice Interpret an `op` from a programm encoded in a `ptr`, saving accounting changes in the `accounter`
    function _interpretOp(Accounter memory accounter, uint256 ptr, uint256 op) internal returns (uint256) {
        // Extract the operation
        uint256 mop = op & Ops.MASK_OP;

        if (mop == Ops.SWAP) {
            ptr = _swap(accounter, ptr, op);
        } else if (mop == Ops.SEND_ALL) {
            ptr = _sendAll(accounter, ptr, op);
        } else if (mop == Ops.RECEIVE_ALL) {
            ptr = _receiveAll(accounter, ptr, op);
        } else if (mop == Ops.ADD_LIQ) {
            ptr = _addLiquidity(accounter, ptr);
        } else if (mop == Ops.RM_LIQ) {
            ptr = _removeLiquidity(accounter, ptr);
        } else {
            // Revert cause of an invalid OP
            revert InvalidOp(op);
        }

        // Return the updated ptr
        return ptr;
    }

    /// @notice Perform a swap operation
    function _swap(Accounter memory accounter, uint256 ptr, uint256 op) internal returns (uint256) {
        uint256 amount;

        bool zeroForOne = (op & Ops.SWAP_DIR) != 0;
        (ptr, amount) = ptr.readUint(16);

        // Get the deltas
        int256 delta0;
        int256 delta1;

        // Take the fee if needed
        if (swapFeePerThousands > 0) {
            uint256 protocolFeeToken0;
            uint256 protocolFeeToken1;
            (delta0, delta1, protocolFeeToken0, protocolFeeToken1) =
                pool.swap(zeroForOne, amount, FEE_BPS, swapFeePerThousands);

            token0State.protocolFees += protocolFeeToken0;
            token1State.protocolFees += protocolFeeToken1;
        } else {
            (delta0, delta1) = pool.swap(zeroForOne, amount, FEE_BPS);
        }

        accounter.accountChange(TOKEN_0, delta0);
        accounter.accountChange(TOKEN_1, delta1);

        return ptr;
    }

    /* -------------------------------------------------------------------------- */
    /*                        Token sending / pulling op's                        */
    /* -------------------------------------------------------------------------- */

    /// @notice Perform the send all operation
    function _sendAll(Accounter memory accounter, uint256 ptr, uint256 op) internal returns (uint256) {
        // Get the right token depending on the input
        address token;
        TokenState storage tokenState;
        (ptr, token, tokenState) = _getTokenFromBoolInPtr(ptr);

        // Get the delta for the current accounting
        int256 delta = accounter.resetChange(token);
        if (delta > 0) revert NegativeAmount();

        // Get the limits
        uint256 minSend = 0;
        uint256 maxSend = type(uint128).max;

        if (op & Ops.ALL_MIN_BOUND != 0) (ptr, minSend) = ptr.readUint(16);
        if (op & Ops.ALL_MAX_BOUND != 0) (ptr, maxSend) = ptr.readUint(16);

        uint256 amount = uint256(-delta);
        if (amount < minSend || amount > maxSend) revert AmountOutsideBounds();

        // Get the recipient of the transfer
        address to;
        (ptr, to) = ptr.readAddress();

        // Decrease the total reserve
        tokenState.totalReserves -= amount;

        // Transfer the tokens
        token.safeTransfer(to, amount);

        return ptr;
    }

    /// @notice Perform the receive all operation
    function _receiveAll(Accounter memory accounter, uint256 ptr, uint256 op) internal returns (uint256) {
        // Get the right token depending on the input
        address token;
        TokenState storage tokenState;
        (ptr, token, tokenState) = _getTokenFromBoolInPtr(ptr);

        // Get the limits
        uint256 minReceive = 0;
        uint256 maxReceive = type(uint128).max;

        if (op & Ops.ALL_MIN_BOUND != 0) (ptr, minReceive) = ptr.readUint(16);
        if (op & Ops.ALL_MAX_BOUND != 0) (ptr, maxReceive) = ptr.readUint(16);

        // Get the delta for the current accounting
        int256 delta = accounter.getChange(token);
        if (delta < 0) revert NegativeReceive();

        // Get the amount to receive
        uint256 amount = uint256(delta);
        if (amount < minReceive || amount > maxReceive) revert AmountOutsideBounds();

        // Perform the transfer
        token.safeTransferFrom(msg.sender, address(this), amount);
        _accountReceived(accounter, tokenState, token);

        return ptr;
    }

    /// @dev Function called after we received token from an account, update our total reserve and the account changes
    function _accountReceived(Accounter memory accounter, TokenState storage tokenState, address token) internal {
        uint256 reserves = tokenState.totalReserves;
        uint256 directBalance = token.balanceOf(address(this));
        uint256 totalReceived = directBalance - reserves;

        accounter.accountChange(token, -totalReceived.toInt256());
        tokenState.totalReserves = directBalance;
    }

    /* -------------------------------------------------------------------------- */
    /*                           Liquidity specific op's                          */
    /* -------------------------------------------------------------------------- */

    /// @notice Perform the add liquidity operation
    function _addLiquidity(Accounter memory accounter, uint256 ptr) internal returns (uint256) {
        address to;
        uint256 maxAmount0;
        uint256 maxAmount1;
        (ptr, to) = ptr.readAddress();
        (ptr, maxAmount0) = ptr.readUint(16);
        (ptr, maxAmount1) = ptr.readUint(16);

        (, int256 delta0, int256 delta1) = pool.addLiquidity(to, maxAmount0, maxAmount1);

        accounter.accountChange(TOKEN_0, delta0);
        accounter.accountChange(TOKEN_1, delta1);

        return ptr;
    }

    /// @notice Perform the remove liquidity operation
    function _removeLiquidity(Accounter memory accounter, uint256 ptr) internal returns (uint256) {
        address token;
        uint256 liq;
        (ptr, token) = ptr.readAddress();
        (ptr, liq) = ptr.readFullUint();

        (int256 delta0, int256 delta1) = pool.removeLiquidity(msg.sender, liq);

        accounter.accountChange(TOKEN_0, delta0);
        accounter.accountChange(TOKEN_1, delta1);

        return ptr;
    }

    /* -------------------------------------------------------------------------- */
    /*                        Internal pure helper method's                       */
    /* -------------------------------------------------------------------------- */

    function _getPc(bytes calldata program) internal pure returns (uint256 ptr, uint256 endPtr) {
        assembly ("memory-safe") {
            ptr := program.offset
            endPtr := add(ptr, program.length)
        }
    }

    function _getTokenFromBoolInPtr(uint256 ptr)
        internal
        view
        returns (uint256, address token, TokenState storage tokenState)
    {
        bool isToken0;
        (ptr, isToken0) = ptr.readBool();

        // Get the right token & state depending on the bool
        if (isToken0) {
            token = TOKEN_0;
            tokenState = token0State;
        } else {
            token = TOKEN_1;
            tokenState = token1State;
        }
        return (ptr, token, tokenState);
    }

    /* -------------------------------------------------------------------------- */
    /*                           External view method's                           */
    /* -------------------------------------------------------------------------- */

    /// @notice Get the current tokens
    function getTokens() external view returns (address token0, address token1) {
        return (TOKEN_0, TOKEN_1);
    }

    /// @notice Get the current pool
    /// @return totalLiquidity
    /// @return reserve0
    /// @return reserve1
    function getPoolState() external view returns (uint256, uint256, uint256) {
        return (pool.totalLiquidity, token0State.totalReserves, token1State.totalReserves);
    }

    /// @notice Get the current token states
    /// @return totalReserves0
    /// @return totalReserves1
    function getReserves() external view returns (uint256, uint256) {
        return (token0State.totalReserves, token1State.totalReserves);
    }

    /// @notice Get the current fees
    function getFees() external view returns (uint256 bps, uint256 protocolFee) {
        return (FEE_BPS, protocolFee);
    }
}