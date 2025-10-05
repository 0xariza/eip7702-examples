// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IVaulteraSmartAccount {
    // Errors
    error InsufficientBalance(uint256 required, uint256 available);
    error InvalidRecipient(address recipient);
    error TransferFailed(address recipient, uint256 amount);
    error UnauthorizedCaller();



    function transferETH(
        address to,
        uint256 amount,
        uint256 feeBps,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external;

    function transferToken(
        address token,
        address to,
        uint256 amount,
        uint256 feeBps,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external;

    function getDomainSeparator() external view returns (bytes32 separator);
}


