// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenData, TokenType} from "./Types.sol";

/// @title IWcBTC
/// @notice Minimal interface for Wrapped cBTC (WETH9-style wrapper on Citrea).
interface IWcBTC {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title TokenGuard
/// @notice Handles wrapping native cBTC to WcBTC on shield, and unwrapping on unshield.
/// @dev ShadePool inherits this contract to gain deposit/withdrawal helpers.
abstract contract TokenGuard {
    /// @notice The canonical Wrapped cBTC contract on Citrea.
    IWcBTC public immutable wcBTC;

    /// @param _wcBTC Address of the deployed WcBTC (WETH9-style) contract.
    constructor(address _wcBTC) {
        require(_wcBTC != address(0), "TokenGuard: zero WcBTC address");
        wcBTC = IWcBTC(_wcBTC);
    }

    // -----------------------------------------------------------------------
    //  Internal helpers
    // -----------------------------------------------------------------------

    /// @notice Pull tokens into the pool for a shield operation.
    /// @dev If `nativeValue` > 0 the caller sent native cBTC which gets wrapped.
    ///      Otherwise we transferFrom WcBTC that the caller pre-approved.
    /// @param token   Token metadata from the commitment preimage.
    /// @param value   Amount to shield (in the token's smallest unit).
    /// @param nativeValue The msg.value allocated for this particular request.
    function _handleShieldDeposit(TokenData calldata token, uint120 value, uint256 nativeValue) internal {
        require(token.tokenType == TokenType.ERC20, "TokenGuard: unsupported token type");
        require(token.tokenAddress == address(wcBTC), "TokenGuard: token must be WcBTC");
        require(token.tokenSubID == 0, "TokenGuard: ERC20 subID must be 0");
        require(value > 0, "TokenGuard: zero value");

        if (nativeValue > 0) {
            // Caller sent native cBTC -- wrap it.
            require(nativeValue == value, "TokenGuard: native value mismatch");
            wcBTC.deposit{value: nativeValue}();
        } else {
            // Caller pre-approved WcBTC -- pull it.
            bool ok = wcBTC.transferFrom(msg.sender, address(this), value);
            require(ok, "TokenGuard: WcBTC transferFrom failed");
        }
    }

    /// @notice Send tokens out of the pool for an unshield operation.
    /// @dev Unwraps WcBTC back to native cBTC and sends to the recipient.
    /// @param recipient Address that receives the native cBTC.
    /// @param value     Amount to unshield (in smallest unit).
    function _handleUnshield(address recipient, uint120 value) internal {
        require(recipient != address(0), "TokenGuard: zero recipient");
        require(value > 0, "TokenGuard: zero unshield value");

        // Unwrap WcBTC → native cBTC
        wcBTC.withdraw(value);

        // Send native cBTC to recipient
        (bool sent,) = recipient.call{value: value}("");
        require(sent, "TokenGuard: native transfer failed");
    }

    /// @notice Allow the contract to receive native cBTC (needed for WcBTC.withdraw).
    receive() external payable {}
}
