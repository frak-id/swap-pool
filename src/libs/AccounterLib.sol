// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

struct Accounter {
    int256 token0Change;
    int256 token1Change;
}

/// @dev Tell to use the lib below for every Accounter instance
using AccounterLib for Accounter global;

/// @title AccounterLib
/// @notice A library for tracking changes to an account.
/// @author KONFeature <https://github.com/KONFeature>
/// @author Modified from (https://github.com/Philogy/singleton-swapper/blob/main/src/libs/AccounterLib.sol) by Philogy
library AccounterLib {
    /// @notice Register a `change` of `isToken0` for the current sender, on the current accounting: `self`.
    function accountChange(Accounter memory self, bool isToken0, int256 change) internal pure {
        if (isToken0) {
            self.token0Change = self.token0Change + change;
        } else {
            self.token1Change = self.token1Change + change;
        }
    }

    /// @notice Register the changes for both token, respectively `token0Change` and `token1Change` for the current
    /// sender, on the current accounting: `self`.
    function accountChange(Accounter memory self, int256 token0Change, int256 token1Change) internal pure {
        self.token0Change = self.token0Change + token0Change;
        self.token1Change = self.token1Change + token1Change;
    }

    /// @notice Reset all the of `isToken0` change for the current sender, on the current accounting: `self`.
    /// @return change The total change for the asset that was cleared.
    function resetChange(Accounter memory self, bool isToken0) internal pure returns (int256 change) {
        // Get the change depending on the token
        if (isToken0) {
            change = self.token0Change;
            self.token0Change = 0;
        } else {
            change = self.token1Change;
            self.token1Change = 0;
        }
    }

    /// @notice Get the total change for the current sender on the `isToken0`, on the current accounting: `self`.
    function getChange(Accounter memory self, bool isToken0) internal pure returns (int256 change) {
        if (isToken0) {
            change = self.token0Change;
        } else {
            change = self.token1Change;
        }
    }
}
