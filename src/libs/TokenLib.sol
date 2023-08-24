// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";

/// @dev Type to manage swappable token, with ease of ease for native token
type Token is address;

/// @dev Tell to use the lib below for every Token instance
using TokenLib for Token global;

/// @dev Tell to use the equals functions for the equals operator
using { equals as == } for Token global;

function equals(Token currency, Token other) pure returns (bool) {
    return Token.unwrap(currency) == Token.unwrap(other);
}

/// @title TokenLib
/// @notice A library for managing a token in the swap pool.
/// @author KONFeature <https://github.com/KONFeature>
library TokenLib {
    using SafeTransferLib for address;

    /// @dev Error throwned when the token is the native token and we try to perform a permit operation
    error PermitOnNativeToken();

    /// @dev Error throwned when the token is the native token and we try to perform a safe transfer operation
    error TransferFromOnNativeToken();

    /// @dev The native token address
    Token private constant NATIVE = Token.wrap(address(0));

    /// @notice Transfer `amount` of `token` to `to`.
    function transfer(Token self, address to, uint256 amount) internal {
        if (self.isNative()) {
            // Perform a native transfer of the amount
            to.safeTransferETH(amount);
        } else {
            // Perform the transfer of the token
            Token.unwrap(self).safeTransfer(to, amount);
        }
    }

    /// @notice Transfer `amount` of `token` to `to` from `from`.
    function transferFrom(Token self, address from, address to, uint256 amount) internal {
        if (self.isNative()) {
            // Check if the caller is the from address, and if the amount match the msg.value, if that's the case we can
            // exit directly
            if (from == msg.sender && amount == msg.value) return;

            // Otherwise revert since we can take perform a transfer from on native token
            revert TransferFromOnNativeToken();
        }

        // Try to perform the transfer
        Token.unwrap(self).safeTransferFrom(from, to, amount);
    }

    /// @notice Check if the current token is a representation of the native token
    function isNative(Token self) internal pure returns (bool) {
        return Token.unwrap(self) == Token.unwrap(NATIVE);
    }

    /// @notice Get the current balance of the caller
    function selfBalance(Token self) internal view returns (uint256) {
        if (self.isNative()) {
            return address(this).balance;
        } else {
            return Token.unwrap(self).balanceOf(address(this));
        }
    }

    /// @notice Get the current balance of `owner`
    function balanceOf(Token self, address owner) internal view returns (uint256) {
        if (self.isNative()) {
            return owner.balance;
        } else {
            return Token.unwrap(self).balanceOf(owner);
        }
    }

    /// @notice Perform the permit op on the given token
    function permit(
        Token self,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        internal
    {
        // Permit is not supported on native token
        if (self.isNative()) revert PermitOnNativeToken();

        // Try to perform the permit operation
        ERC20(Token.unwrap(self)).permit(owner, spender, value, deadline, v, r, s);
    }
}
