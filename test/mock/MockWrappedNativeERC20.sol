// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IWrappedNativeToken } from "src/interfaces/IWrappedNativeToken.sol";
import { MockERC20 } from "./MockERC20.sol";

/// @author KONFeature <https://github.com/KONFeature>
contract MockWrappedNativeERC20 is MockERC20, IWrappedNativeToken {
    using SafeTransferLib for address;

    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    function name() public pure override returns (string memory) {
        return "Wrapped Mock Token";
    }

    function symbol() public pure override returns (string memory) {
        return "wMCK";
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        _burn(msg.sender, wad);
        msg.sender.safeTransferETH(wad);
        emit Withdrawal(msg.sender, wad);
    }
}
