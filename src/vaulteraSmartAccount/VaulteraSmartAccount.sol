// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../account-abstraction/contracts/core/Helpers.sol";
import "../../account-abstraction/contracts/core/BaseAccount.sol";
import "../feeManager/IFeeManager.sol";

/**
 * @title VaulteraSmartAccount
 * @notice Modular smart account compatible with ERC-4337 (Account Abstraction).
 * @dev Supports secure execution, signature validation, and fee management via an external
 *      IFeeManager contract. Enables interaction with ERC20, ERC721, and ERC1155 tokens and
 *      integrates with the EntryPoint.
 */
contract VaulteraSmartAccount is
    BaseAccount,
    IERC165,
    IERC1271,
    ERC1155Holder,
    ERC721Holder
{
    // Fee configuration
    IFeeManager public immutable feeManager;
    IEntryPoint private immutable _entryPoint;

    constructor(address _feeManager, address _entryPointAddress) {
        feeManager = IFeeManager(_feeManager);
        _entryPoint = IEntryPoint(_entryPointAddress);
    }

    // ========================= External =========================

    /**
     * @notice Transfer ETH using a fee permit.
     * @param to Recipient address
     * @param amount Amount of ETH to transfer
     * @param feeBps Fee percentage in basis points from permit
     * @param nonce Nonce for replay protection
     * @param deadline Permit expiration timestamp
     * @param signature Fee permit signature from backend
     */
    function transferETH(
        address to,
        uint256 amount,
        uint256 feeBps,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        _requireForExecute();
        uint256 feeAmount = (amount * feeBps) / 10000;
        feeManager.transferEth{value: amount + feeAmount}(
            address(this),
            to,
            amount,
            feeBps,
            nonce,
            deadline,
            signature
        );
    }

    /**
     * @notice Transfer ERC20 tokens using a fee permit.
     * @param token ERC20 token address
     * @param to Recipient address
     * @param amount Amount of tokens to transfer
     * @param feeBps Fee percentage in basis points from permit
     * @param nonce Nonce for replay protection
     * @param deadline Permit expiration timestamp
     * @param signature Fee permit signature from backend
     */
    function transferToken(
        address token,
        address to,
        uint256 amount,
        uint256 feeBps,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        _requireForExecute();
        feeManager.transferToken(
            address(this),
            token,
            to,
            amount,
            feeBps,
            nonce,
            deadline,
            signature
        );
    }

    /**
     * @notice Get the current domain separator for EIP-712 signing.
     * @return separator The domain separator
     */
    function getDomainSeparator() external view returns (bytes32 separator) {
        return feeManager.getDomainSeparator();
    }

    // ========================= Public (views) =========================

    function entryPoint() public view override returns (IEntryPoint) {
        return _entryPoint;
    }

    /**
     * @notice ERC-1271 signature validation.
     * @param hash The signed hash
     * @param signature Signature bytes
     * @return magicValue The ERC-1271 magic value on success
     */
    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) public view returns (bytes4 magicValue) {
        return
            _checkSignature(hash, signature)
                ? this.isValidSignature.selector
                : bytes4(0xffffffff);
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(
        bytes4 id
    ) public pure override(ERC1155Holder, IERC165) returns (bool) {
        return
            id == type(IERC165).interfaceId ||
            id == type(IAccount).interfaceId ||
            id == type(IERC1271).interfaceId ||
            id == type(IERC1155Receiver).interfaceId ||
            id == type(IERC721Receiver).interfaceId;
    }

    // ========================= Internal =========================

    /**
     * @notice Enables this account to be used through the ERC-4337 EntryPoint.
     * @dev The UserOperation must be signed by this account's private key.
     */
    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override returns (uint256 validationData) {
        return
            _checkSignature(userOpHash, userOp.signature)
                ? SIG_VALIDATION_SUCCESS
                : SIG_VALIDATION_FAILED;
    }

    /**
     * @dev Internal ECDSA signature check against the account address.
     */
    function _checkSignature(
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == address(this);
    }

    /**
     * @dev Restrict execution to self or EntryPoint.
     */
    function _requireForExecute() internal view virtual override {
        require(
            msg.sender == address(this) || msg.sender == address(entryPoint()),
            "not from self or EntryPoint"
        );
    }

    // accept incoming calls (with or without value), to mimic an EOA.
    fallback() external payable {}

    receive() external payable {}
}
