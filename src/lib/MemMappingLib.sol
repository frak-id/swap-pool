// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

type MemMapping is uint256;
type MapKVPair is uint256;

using MemMappingLib for MemMapping global;
using MemMappingLib for MapKVPair global;

/// @title MemMappingLib
/// @notice In memory map of key value pair
/// @dev Store, from the first free mem pointer, on 32 bytes, key-value-key-value-key-value...
/// @dev The free mem pointer is moved after the the mam allocated size (defined during the init)
/// @author KONFeature <https://github.com/KONFeature>
/// @author Modified from (https://github.com/Philogy/singleton-swapper/blob/main/src/libs/MemMappingLib.sol) by Philogy
library MemMappingLib {
    /// @dev Initialize the `map` with a size of `z` key-value pair
    function init(uint256 z) internal pure returns (MemMapping map) {
        assembly ("memory-safe") {
            // Allocate memory: 1 + 2 * size
            map := mload(0x40)
            mstore(map, z)
            let valueOffset := add(map, 0x20)
            let dataSize := mul(z, 0x40)
            mstore(0x40, add(valueOffset, dataSize))
            // Clears potentially dirty free memory.
            calldatacopy(valueOffset, calldatasize(), dataSize)
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                  Logic related to a KeyValue pair directly                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Returns the key of the `kvPair`
    function key(MapKVPair kvPair) internal pure returns (uint256 k) {
        assembly ("memory-safe") {
            k := mload(kvPair)
        }
    }

    /// @dev Returns the value of the `kvPair`
    function value(MapKVPair kvPair) internal pure returns (uint256 v) {
        assembly ("memory-safe") {
            v := mload(add(kvPair, 0x20))
        }
    }

    /// @dev Sets the value of the `kvPair`
    function setValue(MapKVPair kvPair, uint256 v) internal pure {
        assembly ("memory-safe") {
            mstore(add(kvPair, 0x20), v)
        }
    }

    /// @dev Sets the key `k` and value `v` of the `kvPair`
    function set(MapKVPair kvPair, uint256 k, uint256 v) internal pure {
        assembly ("memory-safe") {
            mstore(kvPair, k)
            mstore(add(kvPair, 0x20), v)
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                       Logic related to the MemMapping                      */
    /* -------------------------------------------------------------------------- */

    /// @dev Returns the size of the `map`
    function size(MemMapping map) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := mload(map)
        }
    }

    /// @dev Returns the pair of the `map` at the key `k`
    function getPair(MemMapping map, uint256 k) internal pure returns (MapKVPair kvPair) {
        require(k != 0);

        assembly ("memory-safe") {
            let z := mload(map)
            let baseOffset := add(map, 0x20)
            let i := mod(k, z)
            kvPair := add(mul(i, 0x40), baseOffset)
            let storedKey := mload(kvPair)

            for { } iszero(or(eq(storedKey, k), iszero(storedKey))) { } {
                i := mod(add(i, 1), z)
                kvPair := add(mul(i, 0x40), baseOffset)
                storedKey := mload(kvPair)
            }
        }
    }

    /// @dev Set the new key `k` and `v` value in the `map`
    function set(MemMapping map, uint256 k, uint256 v) internal pure {
        map.getPair(k).set(k, v);
    }

    /// @dev Returns the value of the `map` at the key `k`
    function get(MemMapping map, uint256 k) internal pure returns (bool isNull, uint256 v) {
        MapKVPair pair = map.getPair(k);
        isNull = pair.key() == 0;
        v = pair.value();
    }
}
