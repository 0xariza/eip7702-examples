// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IFeeManager.sol";

/**
 * @title FeeManager
 * @notice Manages ETH and ERC20 transfers with fee collection and EIP-712 permit-based authorization.
 */

contract FeeManager is IFeeManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========================= State =========================
    address public treasury;
    uint256 public systemFeePercentage; // in basis points (100 = 1%)
    uint256 public maximumFeePercentage; // in basis points (1000 = 10%)

    address public feeSigner;
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    // EIP-712 Domain Separator
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 internal constant _FEE_PERMIT_TYPEHASH =
        keccak256(
            "FeePermit(address account,address to,uint256 amount,uint256 feeBps,uint256 nonce,uint256 deadline)"
        );
    bytes32 internal constant _TOKEN_FEE_PERMIT_TYPEHASH =
        keccak256(
            "TokenFeePermit(address account,address token,address to,uint256 amount,uint256 feeBps,uint256 nonce,uint256 deadline)"
        );
    bytes32 private immutable _domainSeparator;

    // Note: structs are declared in IFeeManager

    // Expose typehashes for tests and clients
    function FEE_PERMIT_TYPEHASH() external pure returns (bytes32) {
        return _FEE_PERMIT_TYPEHASH;
    }

    function TOKEN_FEE_PERMIT_TYPEHASH() external pure returns (bytes32) {
        return _TOKEN_FEE_PERMIT_TYPEHASH;
    }

    constructor(
        address _treasury,
        uint256 _systemFeePercentage,
        uint256 _maximumFeePercentage,
        address _feeSigner,
        address _initialOwner
    ) Ownable(_initialOwner) {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_feeSigner == address(0)) revert ZeroAddress();
        if (_systemFeePercentage > 1000)
            revert FeePercentageTooHigh(_systemFeePercentage);
        if (_maximumFeePercentage > 1000)
            revert MaximumFeePercentageTooHigh(_maximumFeePercentage);
        if (_systemFeePercentage > _maximumFeePercentage)
            revert SystemFeeExceedsMaximum(
                _systemFeePercentage,
                _maximumFeePercentage
            );

        treasury = _treasury;
        systemFeePercentage = _systemFeePercentage;
        maximumFeePercentage = _maximumFeePercentage;
        feeSigner = _feeSigner;

        _domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("FeeManager")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    // ========================= Admin =========================

    function updateTreasury(address _newTreasury) external onlyOwner {
        if (_newTreasury == address(0)) revert ZeroAddress();
        address oldTreasury = treasury;
        treasury = _newTreasury;
        emit TreasuryUpdated(oldTreasury, _newTreasury);
    }

    function updateFeeConfig(
        uint256 _newPercentage,
        uint256 _newMaximumPercentage
    ) external onlyOwner {
        if (_newPercentage > 1000) revert FeePercentageTooHigh(_newPercentage);
        if (_newMaximumPercentage > 1000)
            revert MaximumFeePercentageTooHigh(_newMaximumPercentage);
        if (_newPercentage > _newMaximumPercentage)
            revert SystemFeeExceedsMaximum(
                _newPercentage,
                _newMaximumPercentage
            );

        systemFeePercentage = _newPercentage;
        maximumFeePercentage = _newMaximumPercentage;

        emit FeeConfigUpdated(_newPercentage, _newMaximumPercentage);
    }

    function updateFeeSigner(address _newFeeSigner) external onlyOwner {
        if (_newFeeSigner == address(0)) revert ZeroAddress();
        address oldSigner = feeSigner;
        feeSigner = _newFeeSigner;
        emit FeeSignerUpdated(oldSigner, _newFeeSigner);
    }

    

    /**
     * @notice Transfer ETH using a signed fee permit.
     * @dev Called by a smart account to execute an ETH transfer with fee.
     * @param account Smart account address paying the fee
     * @param to Recipient address
     * @param amount Amount of ETH to transfer
     * @param feeBps Fee percentage in basis points from permit
     * @param nonce Permit nonce for replay protection
     * @param deadline Permit expiration timestamp
     * @param signature Fee permit signature
     */
    function transferEth(
        address account,
        address to,
        uint256 amount,
        uint256 feeBps,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external payable nonReentrant {
        IFeeManager.FeePermit memory permit = IFeeManager.FeePermit({
            account: account,
            to: to,
            amount: amount,
            feeBps: feeBps,
            nonce: nonce,
            deadline: deadline
        });

        if (!_verifyFeePermit(permit, signature)) {
            revert InvalidPermit();
        }

        // Execute transfer with permitted fee (inlined)
        if (to == address(0)) {
            revert InvalidRecipient(address(0));
        }
        if (amount == 0) {
            revert InvalidAmount(amount);
        }

        uint256 feeAmount = _calculateFee(amount, feeBps);
        uint256 totalRequired = amount + feeAmount;
        if (msg.value != totalRequired) {
            revert IncorrectMsgValue(totalRequired, msg.value);
        }
        uint256 contractBalance = address(this).balance;
        if (contractBalance < totalRequired) {
            revert InsufficientBalance(totalRequired, contractBalance);
        }

        // Mark nonce as used (per account)
        usedNonces[account][nonce] = true;

        if (feeAmount > 0) {
            address treasuryAddress = treasury;
            (bool feeSuccess, ) = treasuryAddress.call{value: feeAmount}("");
            if (!feeSuccess) {
                revert FeeTransferFailed(treasuryAddress, feeAmount);
            }
            emit FeeCollected(treasuryAddress, feeAmount, amount);
        }

        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed(to, amount);
        }

        emit ETHTransferred(to, amount, feeAmount, feeBps > 0);
    }

    /**
     * @notice Transfer ERC20 tokens using a signed fee permit.
     * @dev Called by a smart account to execute a token transfer with fee.
     * @param account Smart account address paying the fee
     * @param token ERC20 token address
     * @param to Recipient address
     * @param amount Amount of tokens to transfer
     * @param feeBps Fee percentage in basis points from permit
     * @param nonce Permit nonce for replay protection
     * @param deadline Permit expiration timestamp
     * @param signature Fee permit signature
     */
    function transferToken(
        address account,
        address token,
        address to,
        uint256 amount,
        uint256 feeBps,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        IFeeManager.TokenFeePermit memory permit = IFeeManager.TokenFeePermit({
            account: account,
            token: token,
            to: to,
            amount: amount,
            feeBps: feeBps,
            nonce: nonce,
            deadline: deadline
        });

        if (!_verifyTokenFeePermit(permit, signature)) {
            revert InvalidPermit();
        }

        // Execute transfer with permitted fee (inlined)
        if (to == address(0)) {
            revert InvalidRecipient(address(0));
        }
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
        uint256 feeAmount = _calculateFee(amount, feeBps);
        uint256 totalRequired = amount + feeAmount;
        uint256 allowance = IERC20(token).allowance(account, address(this));
        if (allowance < totalRequired) {
            revert InsufficientTokenAllowance(totalRequired, allowance);
        }

        // Mark nonce as used (per account)
        usedNonces[account][nonce] = true;
        if (feeAmount > 0) {
            address treasuryAddress = treasury;
            IERC20(token).safeTransferFrom(account, treasuryAddress, feeAmount);
            emit FeeCollected(treasuryAddress, feeAmount, amount);
        }
        IERC20(token).safeTransferFrom(account, to, amount);
        emit TokenTransferred(token, to, amount, feeAmount, feeBps > 0);
       
    }

    // ========================= Public (views) =========================

    /**
     * @notice Returns the EIP-712 domain separator used for permits.
     */
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return _domainSeparator;
    }

    /**
     * @notice Get the current domain separator for EIP-712 signing.
     * @return separator The domain separator
     */
    function getDomainSeparator() external view returns (bytes32 separator) {
        return DOMAIN_SEPARATOR();
    }

    // ========================= Internal helpers =========================

    /**
     * @dev Hash a FeePermit struct for EIP-712 signing.
     */
    function _hashFeePermit(
        IFeeManager.FeePermit memory permit
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _FEE_PERMIT_TYPEHASH,
                    permit.account,
                    permit.to,
                    permit.amount,
                    permit.feeBps,
                    permit.nonce,
                    permit.deadline
                )
            );
    }

    /**
     * @dev Hash a TokenFeePermit struct for EIP-712 signing.
     */
    function _hashTokenFeePermit(
        IFeeManager.TokenFeePermit memory permit
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _TOKEN_FEE_PERMIT_TYPEHASH,
                    permit.account,
                    permit.token,
                    permit.to,
                    permit.amount,
                    permit.feeBps,
                    permit.nonce,
                    permit.deadline
                )
            );
    }

    /**
     * @dev Verify a fee permit signature.
     */
    function _verifyFeePermit(
        IFeeManager.FeePermit memory permit,
        bytes memory signature
    ) internal view returns (bool) {
        if (block.timestamp > permit.deadline) {
            revert PermitExpired(permit.deadline, block.timestamp);
        }

        if (usedNonces[permit.account][permit.nonce]) {
            revert NonceUsed(permit.nonce);
        }

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                _hashFeePermit(permit)
            )
        );

        return ECDSA.recover(digest, signature) == feeSigner;
    }

    /**
     * @dev Verify a token fee permit signature.
     */
    function _verifyTokenFeePermit(
        IFeeManager.TokenFeePermit memory permit,
        bytes memory signature
    ) internal view returns (bool) {
        if (block.timestamp > permit.deadline) {
            revert PermitExpired(permit.deadline, block.timestamp);
        }

        if (usedNonces[permit.account][permit.nonce]) {
            revert NonceUsed(permit.nonce);
        }

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                _hashTokenFeePermit(permit)
            )
        );

        return ECDSA.recover(digest, signature) == feeSigner;
    }

    /**
     * @dev Calculate fee amount from basis points. Falls back to system fee when custom is 0.
     */
    function _calculateFee(
        uint256 amount,
        uint256 customFeeBps
    ) internal view returns (uint256) {
        if (customFeeBps == 0) {
            return (amount * systemFeePercentage) / 10000;
        }
        if (customFeeBps > maximumFeePercentage) {
            revert CustomFeeExceedsMaximum(customFeeBps, maximumFeePercentage);
        }
        return (amount * customFeeBps) / 10000;
    }
    receive() external payable {}
}
