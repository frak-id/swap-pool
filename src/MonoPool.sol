// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { Pool } from "./libs/PoolLib.sol";
import { Accounter } from "./libs/AccounterLib.sol";
import { Token } from "./libs/TokenLib.sol";
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
    uint256 private constant MAX_PROTOCOL_FEE = 500;

    /// @dev The token state to handle reserves & protocol fees
    struct TokenState {
        uint128 totalReserves;
        uint128 protocolFees;
    }

    /* -------------------------------------------------------------------------- */
    /*                               Custom error's                               */
    /* -------------------------------------------------------------------------- */

    error InvalidOp(uint256 op);
    error LeftOverDelta();
    error DeadlineExpired();
    error NegativeSend();
    error NegativeReceive();
    error AmountOutsideBounds();
    error NotFeeReceiver();
    error Swap0Amount();

    /// @dev 'bytes4(keccak256("Swap0Amount()"))'
    uint256 private constant _SWAP_0_AMOUNT_SELECTOR = 0x5509f2e4;

    /* -------------------------------------------------------------------------- */
    /*                                   Event's                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev Event emitted after a swap
    event Swap(bool zeroForOne, uint256 amountIn);

    /// @dev Event emitted after a liquidity update (addition or suppression)
    event LiquidityUpdate(address indexed provider, int256 amount0, int256 amount1);

    /// @dev Event emitted after a protocol fee update
    event ProtocolFeeUpdate(address feesColector, uint256 protocolFee);

    /* -------------------------------------------------------------------------- */
    /*                                   Storage                                  */
    /* -------------------------------------------------------------------------- */

    // slither-disable-start naming-convention

    /// @dev The token's we will use for the pool
    Token private immutable TOKEN_0;
    Token private immutable TOKEN_1;

    /// @dev The fee that will be taken from each swaps
    uint256 private immutable FEE_BPS;

    // slither-disable-end naming-convention

    /// @dev The fee that will be taken from each swaps
    uint256 private protocolFee;

    /// @dev The receiver for the swap fees
    address private feeReceiver;

    /// @dev The pool managed by this contract
    Pool private pool;

    /// @dev The current token state's
    TokenState private token0State;
    TokenState private token1State;

    /* -------------------------------------------------------------------------- */
    /*                                 Constructor                                */
    /* -------------------------------------------------------------------------- */

    constructor(address token0, address token1, uint256 feeBps, address _feeReceiver, uint256 _protocolFee) payable {
        require(feeBps < BPS);
        require(_protocolFee < MAX_PROTOCOL_FEE);
        // We can only have one 0 address (representing native pool)
        require(token0 != address(0) || token1 != address(0));

        // If no fees receiver passed, pass 0 arguments
        if (_feeReceiver == address(0)) {
            require(_protocolFee == 0);
        }

        // Save base pool info's
        FEE_BPS = feeBps;
        TOKEN_0 = Token.wrap(token0);
        TOKEN_1 = Token.wrap(token1);

        // Save info's about protocol receiver
        feeReceiver = _feeReceiver;
        protocolFee = _protocolFee;
    }

    /* -------------------------------------------------------------------------- */
    /*                           External write method's                          */
    /* -------------------------------------------------------------------------- */

    /// @notice Update the fee receiver and the fee amount
    /// @dev Only the current fee receiver can update the fee receiver and the amount
    /// @dev The protocol can decide to stop receiving fees, by doing so he need to send the 0 address & 0 protocol fees
    /// @param _feeReceiver The new fee receiver
    /// @param _protocolFee The new fee amount per thousand
    function updateFeeReceiver(address _feeReceiver, uint256 _protocolFee) external {
        if (feeReceiver != msg.sender) revert NotFeeReceiver();

        require(_protocolFee < MAX_PROTOCOL_FEE);

        if (_feeReceiver == address(0)) {
            require(_protocolFee == 0);
        }

        feeReceiver = _feeReceiver;
        protocolFee = _protocolFee;

        // Emit event
        emit ProtocolFeeUpdate(_feeReceiver, _protocolFee);
    }

    /**
     * @notice Execute a program of operations on pools. The `program` is a serialized list of operations, encoded in a
     * specific format.
     * @dev This function uses a non-ABI encoding to ensure a custom set of operations, each taking on a different
     * amount of data while keeping calldata size minimal. It is not reentrant.
     * @param program Serialized list of operations, with each operation consisting of an 8-bit operation specifier and
     * parameters. The structure is as follows:
     *  For every operation:
     *    1 byte:  8-bit operation (4-bits operation id and 4-bits flags)
     *    n bytes: opcode data
     * Refer to the function documentation for details on individual operations.
     */
    function execute(bytes calldata program) external payable nonReentrant {
        (uint256 ptr, uint256 endPtr) = _getPc(program);

        // Initialize the accounter
        Accounter memory accounter = Accounter(0, 0);

        // Interpret each operations
        uint256 op;
        while (ptr < endPtr) {
            (ptr, op) = ptr.readUint8();
            ptr = _interpretOp(accounter, ptr, op);
        }

        // If there are any leftover deltas, revert
        if (accounter.token0Change != 0 || accounter.token1Change != 0) revert LeftOverDelta();
    }

    /* -------------------------------------------------------------------------- */
    /*                           Internal write method's                          */
    /* -------------------------------------------------------------------------- */

    /// @notice Interpret an `op` from a programm encoded in a `ptr`, saving accounting changes in the `accounter`
    function _interpretOp(Accounter memory accounter, uint256 ptr, uint256 op) internal returns (uint256) {
        // Extract the operation
        uint256 mop = op & Ops.MASK_OP;

        if (mop == Ops.SWAP) {
            return _swap(accounter, ptr, op);
        }

        // Send & Receive ALL op's
        if (mop == Ops.RECEIVE_ALL) {
            return _receiveAll(accounter, ptr, op);
        }
        if (mop == Ops.SEND_ALL) {
            return _sendAll(accounter, ptr, op);
        }

        // Send & Receive op's
        if (mop == Ops.RECEIVE) {
            return _receive(accounter, ptr);
        }
        if (mop == Ops.SEND) {
            return _send(accounter, ptr);
        }

        // Permit helper's
        if (mop == Ops.PERMIT_WITHDRAW_VIA_SIG) {
            return _permitViaSig(ptr);
        }

        // Add & Remove liquidity op's
        if (mop == Ops.ADD_LIQ) {
            return _addLiquidity(accounter, ptr);
        }
        if (mop == Ops.RM_LIQ) {
            return _removeLiquidity(accounter, ptr);
        }

        // Claim fees op's
        if (mop == Ops.CLAIM_ALL_FEES) {
            return _claimFees(accounter, ptr);
        }

        // Revert cause of an invalid OP
        revert InvalidOp(op);
    }

    /// @notice Perform a swap operation
    function _swap(Accounter memory accounter, uint256 ptr, uint256 op) internal returns (uint256) {
        uint256 amount;

        bool zeroForOne = (op & Ops.SWAP_DIR) != 0;
        (ptr, amount) = ptr.readUint128();

        // If we got a deadline, ensure we didn't go through it
        if ((op & Ops.SWAP_DEADLINE) != 0) {
            uint256 deadline;
            (ptr, deadline) = ptr.readUint48();
            if (deadline < block.timestamp) revert DeadlineExpired();
        }

        // If we got a swap fee, deduce it from the amount to swap
        uint256 swapFee;
        unchecked {
            swapFee = (amount * protocolFee) / BPS;
            // Decrease the amount of the fees we will take
            amount = amount - swapFee;
        }

        // Get the deltas
        int256 delta0;
        int256 delta1;

        // Perform the swap and compute the delta
        (delta0, delta1) = pool.swap(zeroForOne, amount, FEE_BPS);

        // If we got either of one to 0, revert cause of swapping 0 amount
        assembly {
            if or(iszero(delta0), iszero(delta1)) {
                mstore(0x00, _SWAP_0_AMOUNT_SELECTOR)
                revert(0x1c, 0x04)
            }
        }

        // Emit the swap event
        emit Swap(zeroForOne, amount);

        // Then register the changes (depending on the direction, add the swap fees)
        // We can perform all of this stuff in an uncheck block since all the value has been checked before
        // If he swap fee cause an overflow, it would be triggered before with the swap amount directly
        unchecked {
            if (zeroForOne && swapFee != 0) {
                accounter.accountChange(delta0 + swapFee.toInt256(), delta1);
                // Save protocol fee
                token0State.protocolFees = token0State.protocolFees + swapFee.toUint128();
            } else if (swapFee != 0) {
                accounter.accountChange(delta0, delta1 + swapFee.toInt256());
                // Save protocol fee
                token1State.protocolFees = token1State.protocolFees + swapFee.toUint128();
            } else {
                accounter.accountChange(delta0, delta1);
            }
        }

        return ptr;
    }

    /* -------------------------------------------------------------------------- */
    /*                        Token sending / pulling op's                        */
    /* -------------------------------------------------------------------------- */

    /// @notice Perform the receive operation
    function _receive(Accounter memory accounter, uint256 ptr) internal returns (uint256) {
        // Get the right token depending on the input
        Token token;
        TokenState storage tokenState;
        (ptr, token, tokenState,) = _getTokenFromBoolInPtr(ptr);

        // Get the amount
        uint256 amount;
        (ptr, amount) = ptr.readUint128();

        // Perform the transfer
        token.transferFromSender(address(this), amount);

        // Mark the reception state
        _accountReceived(accounter, tokenState, token, amount);

        return ptr;
    }

    /// @notice Perform the send operation
    function _send(Accounter memory accounter, uint256 ptr) internal returns (uint256) {
        // Get address & token state
        Token token;
        TokenState storage tokenState;
        bool isToken0;
        (ptr, token, tokenState, isToken0) = _getTokenFromBoolInPtr(ptr);

        // Get receiver & amount
        address to;
        uint256 amount;
        (ptr, to) = ptr.readAddress();
        (ptr, amount) = ptr.readUint128();

        // Register the account changes
        accounter.accountChange(isToken0, amount.toInt256());
        tokenState.totalReserves = tokenState.totalReserves - amount.toUint128();

        // Simply transfer the tokens
        token.transfer(to, amount);

        return ptr;
    }

    /* -------------------------------------------------------------------------- */
    /*                      Token sending / pulling ALL op's                      */
    /* -------------------------------------------------------------------------- */

    /// @notice Perform the send all operation
    function _sendAll(Accounter memory accounter, uint256 ptr, uint256 op) internal returns (uint256) {
        // Get the right token depending on the input
        Token token;
        TokenState storage tokenState;
        bool isToken0;
        (ptr, token, tokenState, isToken0) = _getTokenFromBoolInPtr(ptr);

        // Get the delta for the current accounting
        int256 delta = accounter.resetChange(isToken0);
        if (delta > 0) revert NegativeSend();

        // Get the limits
        uint256 minSend = 0;
        uint256 maxSend = type(uint128).max;

        if (op & Ops.ALL_MIN_BOUND != 0) (ptr, minSend) = ptr.readUint128();
        if (op & Ops.ALL_MAX_BOUND != 0) (ptr, maxSend) = ptr.readUint128();

        uint256 amount = uint256(-delta);
        if (amount < minSend || amount > maxSend) revert AmountOutsideBounds();

        // Get the recipient of the transfer
        address to;
        (ptr, to) = ptr.readAddress();

        // Decrease the total reserve
        tokenState.totalReserves = tokenState.totalReserves - amount.toUint128();

        // Simply transfer the tokens
        token.transfer(to, amount);

        return ptr;
    }

    /// @notice Perform the receive all operation
    function _receiveAll(Accounter memory accounter, uint256 ptr, uint256 op) internal returns (uint256) {
        // Get the right token depending on the input
        Token token;
        TokenState storage tokenState;
        bool isToken0;
        (ptr, token, tokenState, isToken0) = _getTokenFromBoolInPtr(ptr);

        // Get the limits
        uint256 minReceive = 0;
        uint256 maxReceive = type(uint128).max;

        if (op & Ops.ALL_MIN_BOUND != 0) (ptr, minReceive) = ptr.readUint128();
        if (op & Ops.ALL_MAX_BOUND != 0) (ptr, maxReceive) = ptr.readUint128();

        // Get the delta for the current accounting
        int256 delta = accounter.getChange(isToken0);
        if (delta < 0) revert NegativeReceive();

        // Get the amount to receive
        uint256 amount = uint256(delta);
        if (amount < minReceive || amount > maxReceive) revert AmountOutsideBounds();

        // Perform the transfer
        token.transferFromSender(address(this), amount);

        // Mark the reception state
        _accountReceived(accounter, tokenState, token, amount);

        return ptr;
    }

    /// @dev Function called after we received token from an account, update our total reserve and the account changes
    function _accountReceived(
        Accounter memory accounter,
        TokenState storage tokenState,
        Token token,
        uint256 targetAmount
    )
        internal
    {
        uint256 directBalance = token.selfBalance();
        uint256 totalReceived = directBalance - tokenState.totalReserves;

        // If we got more than the target amount, add the overflow as protocol fees
        if (totalReceived > targetAmount) {
            uint256 overflow = totalReceived - targetAmount;
            tokenState.protocolFees += overflow.toUint128();
            totalReceived = targetAmount;
        }

        // Register the change for either token 0 or 1 (based on the equality check)
        accounter.accountChange(token == TOKEN_0, -totalReceived.toInt256());
        // Increase the total reservices for this token state
        tokenState.totalReserves = directBalance.toUint128();
    }

    /* -------------------------------------------------------------------------- */
    /*                           Liquidity specific op's                          */
    /* -------------------------------------------------------------------------- */

    /// @notice Perform the add liquidity operation
    function _addLiquidity(Accounter memory accounter, uint256 ptr) internal returns (uint256) {
        uint256 maxAmount0;
        uint256 maxAmount1;
        (ptr, maxAmount0) = ptr.readUint128();
        (ptr, maxAmount1) = ptr.readUint128();

        // Add the liquidity to the pool
        (int256 delta0, int256 delta1) = pool.addLiquidity(msg.sender, maxAmount0, maxAmount1);

        // Register the account changes
        accounter.accountChange(delta0, delta1);

        // Send the event
        emit LiquidityUpdate(msg.sender, delta0, delta1);

        return ptr;
    }

    /// @notice Perform the remove liquidity operation
    function _removeLiquidity(Accounter memory accounter, uint256 ptr) internal returns (uint256) {
        uint256 liq;
        (ptr, liq) = ptr.readUint256();

        // Remove the liquidity from the pool
        (int256 delta0, int256 delta1) = pool.removeLiquidity(msg.sender, liq);

        // Register the account changes
        accounter.accountChange(delta0, delta1);

        // Send the event
        emit LiquidityUpdate(msg.sender, delta0, delta1);

        return ptr;
    }

    /// @notice Perform the claim fees operation
    function _claimFees(Accounter memory accounter, uint256 ptr) internal returns (uint256) {
        // Ensure the sender of the message is the fee receiver
        if (feeReceiver != msg.sender) revert NotFeeReceiver();

        // Then check each tokens he has to claims
        uint256 protocolFees0 = token0State.protocolFees;
        uint256 protocolFees1 = token1State.protocolFees;

        // Update the state only if he got something to claim
        if (protocolFees0 != 0) {
            accounter.accountChange(true, -(protocolFees0.toInt256()));
            token0State.protocolFees = 0;
        }
        if (protocolFees1 != 0) {
            accounter.accountChange(false, -(protocolFees1.toInt256()));
            token1State.protocolFees = 0;
        }

        return ptr;
    }

    /* -------------------------------------------------------------------------- */
    /*                              Token helper op's                             */
    /* -------------------------------------------------------------------------- */

    /// @notice Perform the permit operation
    function _permitViaSig(uint256 ptr) internal returns (uint256) {
        Token token;
        TokenState storage tokenState;
        uint256 amount;
        uint256 deadline;
        uint256 v;
        bytes32 r;
        bytes32 s;

        (ptr, token, tokenState,) = _getTokenFromBoolInPtr(ptr);
        (ptr, amount) = ptr.readUint128();
        (ptr, deadline) = ptr.readUint48();
        (ptr, v) = ptr.readUint8();
        (ptr, r) = ptr.readBytes32();
        (ptr, s) = ptr.readBytes32();

        // Perform the permit operation
        token.permit(msg.sender, address(this), amount, deadline, uint8(v), r, s);

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
        returns (uint256, Token token, TokenState storage tokenState, bool isToken0)
    {
        (ptr, isToken0) = ptr.readBool();

        // Get the right token & state depending on the bool
        if (isToken0) {
            token = TOKEN_0;
            tokenState = token0State;
        } else {
            token = TOKEN_1;
            tokenState = token1State;
        }
        return (ptr, token, tokenState, isToken0);
    }

    /* -------------------------------------------------------------------------- */
    /*                           External view method's                           */
    /* -------------------------------------------------------------------------- */

    /// @notice Get the current tokens
    function getTokens() external view returns (Token token0, Token token1) {
        return (TOKEN_0, TOKEN_1);
    }

    /// @notice Get the current pool
    /// @return totalLiquidity
    /// @return reserve0
    /// @return reserve1
    function getPoolState() external view returns (uint256, uint256, uint256) {
        return (pool.totalLiquidity, pool.reserves0, pool.reserves1);
    }

    /// @notice Get the current pool position of the given `liquidityProvider`
    /// @return position
    function getPosition(address liquidityProvider) external view returns (uint256) {
        return pool.positions[liquidityProvider];
    }

    /// @notice Get the current token states
    /// @return totalReserves0
    /// @return totalReserves1
    function getReserves() external view returns (uint256, uint256) {
        return (token0State.totalReserves, token1State.totalReserves);
    }

    /// @notice Get the current protocol fees
    /// @return protocolFees0
    /// @return protocolFees1
    function getProtocolFees() external view returns (uint256, uint256) {
        return (token0State.protocolFees, token1State.protocolFees);
    }

    /// @notice Get the current fees
    /// @return feeBps
    /// @return protocolFee
    function getFees() external view returns (uint256, uint256) {
        return (FEE_BPS, protocolFee);
    }

    /// @dev Returns the `amountOut` of token that will be received in exchange of `inAmount` in the direction
    /// `zeroForOne`.
    function estimateSwap(
        uint256 inAmount,
        bool zeroForOne
    )
        external
        view
        returns (uint256 outAmount, uint256 feeAmount, uint256 lpFee)
    {
        // Compute the liquidity providers fee
        lpFee = inAmount * FEE_BPS / BPS;

        // Deduce the swap fee from the protocol
        feeAmount = (inAmount * protocolFee) / BPS;
        inAmount -= feeAmount;

        // Get our pour reservices
        uint256 reserves0 = pool.reserves0;
        uint256 reserves1 = pool.reserves1;

        if (zeroForOne) {
            outAmount = reserves1 - (reserves0 * reserves1) / (reserves0 + inAmount * (BPS - FEE_BPS) / BPS);
        } else {
            outAmount = reserves0 - (reserves0 * reserves1) / (reserves1 + inAmount * (BPS - FEE_BPS) / BPS);
        }
    }
}
