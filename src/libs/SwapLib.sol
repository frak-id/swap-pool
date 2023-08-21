// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { SafeCastLib } from "solady/utils/SafeCastLib.sol";

uint256 constant BPS = 10_000;

/// @title SwapLib
/// @notice Library for calculating swap amounts and reserves
/// @author KONFeature <https://github.com/KONFeature>
/// @author Modified from (https://github.com/Philogy/singleton-swapper/blob/main/src/libs/SwapLib.sol) by Phylogy
library SwapLib {
    using SafeCastLib for uint256;

    error MathOverflow();
    error TooLargeSwap();

    /// @notice Calculate a swap amount given a pair reserves, direction and feeBps
    function swap(
        uint256 reserves0,
        uint256 reserves1,
        bool zeroForOne,
        uint256 amount,
        uint256 feeBps
    )
        internal
        pure
        returns (uint256 newReserves0, uint256 newReserves1, int256 delta0, int256 delta1)
    {
        if (zeroForOne) {
            delta0 = amount.toInt256();
            (newReserves0, newReserves1) = swapXForY(reserves0, reserves1, amount, feeBps);
            delta1 = newReserves1.toInt256() - reserves1.toInt256();
        } else {
            delta1 = amount.toInt256();
            (newReserves1, newReserves0) = swapXForY(reserves1, reserves0, amount, feeBps);
            delta0 = newReserves0.toInt256() - reserves0.toInt256();
        }
    }

    /// @notice Calculates the `newX` and `newY` of a pool after swapping `amount` from the current reserve `x` and `y`
    /// @notice Applying `feeBps` fee to the pool
    /// @dev It will also ensure that the user isn't swapping more than the reserves, too prevent too large
    /// liquidity movment
    function swapXForY(
        uint256 x,
        uint256 y,
        uint256 amount,
        uint256 feeBps
    )
        internal
        pure
        returns (uint256 newX, uint256 newY)
    {
        // TODO: Surely more gas opti possible here
        unchecked {
            if (amount > x) revert TooLargeSwap();
            if (amount > amount + x) revert MathOverflow();
            newX = x + amount;

            if (x > x * y || x > x + amount * (BPS - feeBps) / BPS) revert MathOverflow();
            newY = (x * y) / (x + amount * (BPS - feeBps) / BPS);
        }
    }
}
