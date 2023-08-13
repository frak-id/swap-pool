// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { MemMappingLib, MemMapping, MapKVPair } from "./MemMappingLib.sol";

/// @dev Define a struct to hold the accounting state.
struct Accounter {
    MemMapping map;
    uint256 totalNonZero;
}

/// @dev Tell to use the lib below for every Accounter instance
using AccounterLib for Accounter global;

/// @title AccounterLib
/// @notice A library for tracking changes to an account.
/// @author KONFeature <https://github.com/KONFeature>
/// @author Modified from (https://github.com/Philogy/singleton-swapper/blob/main/src/libs/AccounterLib.sol) by Philogy
library AccounterLib {
    function init(Accounter memory self, uint256 mapSize) internal pure {
        self.map = MemMappingLib.init(mapSize);
    }

    /// @notice Register a `change` of `asset` for the current sender, on the current accounting: `self`.
    function accountChange(Accounter memory self, address asset, int256 change) internal pure {
        uint256 key = _toKey(asset);
        MapKVPair pair = self.map.getPair(key);
        int256 prevTotalChange = int256(pair.value());
        int256 newTotalChange = prevTotalChange + change;

        if (prevTotalChange == 0) self.totalNonZero++;
        if (newTotalChange == 0) self.totalNonZero--;

        // Unsafe cast to ensure negative numbers can also be stored.
        pair.set(key, uint256(newTotalChange));
    }

    /// @notice Reset all the of `asset` for the current sender, on the current accounting: `self`.
    /// @return change The total change for the asset that was cleared.
    function resetChange(Accounter memory self, address asset) internal pure returns (int256 change) {
        uint256 key = _toKey(asset);
        MapKVPair pair = self.map.getPair(key);
        change = int256(pair.value());

        if (change != 0) self.totalNonZero--;

        pair.set(key, 0);
    }

    /// @notice Get the total change for the current sender on the `asset`, on the current accounting: `self`.
    function getChange(Accounter memory self, address asset) internal pure returns (int256) {
        (, uint256 rawValue) = self.map.get(_toKey(asset));
        return int256(rawValue);
    }

    /// @dev Map an asset address to a key to be used inside our accounting map.
    function _toKey(address asset) private pure returns (uint256 k) {
        assembly ("memory-safe") {
            k := asset
        }
    }
}
