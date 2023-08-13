// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Ops
/// @notice This library contains all the operations that can be performed by the swap contracts
/// @author KONFeature <https://github.com/KONFeature>
/// @author Modified from Philogy (https://github.com/Philogy/singleton-swapper/blob/main/src/Ops.sol) by Philogy
library Ops {
    /// @dev The mask used to extract the operation type
    uint256 internal constant MASK_OP = 0xf0;

    /// @dev The Ops for the swap operation
    uint256 internal constant SWAP = 0x00;

    /// @dev The mask used to extract the operation direction
    uint256 internal constant SWAP_DIR = 0x01;

    /// @dev The Ops for the send all token operation (from pool to user)
    uint256 internal constant SEND_ALL = 0x10;

    /// @dev The Ops for the receive all token operation (from user to pool)
    uint256 internal constant RECEIVE_ALL = 0x20;

    /// @dev The Ops for the send token operation (from pool to user)
    uint256 internal constant SEND = 0x30;

    /// @dev The Ops for the receive token operation (from user to pool)
    uint256 internal constant RECEIVE = 0x40;

    /// @dev The Ops for the permit operation (using EIP-2612)
    uint256 internal constant PERMIT_WITHDRAW_VIA_SIG = 0x50;

    /// @dev The Ops for the add liquidity operation
    uint256 internal constant ADD_LIQ = 0x60;

    /// @dev The Ops for the remove liquidity operation
    uint256 internal constant RM_LIQ = 0x70;

    /// @dev The Ops for the claim fees operation from the operator
    uint256 internal constant CLAIM_ALL_FEES = 0x80;

    /// @dev The minimum amount of token for the `ALL` operations (0001)
    uint256 internal constant ALL_MIN_BOUND = 0x01;
    /// @dev The maximum amount of token for the `ALL` operations (0010)
    uint256 internal constant ALL_MAX_BOUND = 0x02;

    /// @dev The mask used to handle native token (wrap or unwrap) (0100)
    uint256 internal constant UNWRAP_NATIVE = 0x04;
}
