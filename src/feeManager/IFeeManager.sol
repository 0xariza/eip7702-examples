// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IFeeManager
 * @notice Interface for managing ETH and ERC20 transfers with fee collection and EIP-712 permits.
 */
interface IFeeManager {
    // Structs
    struct FeePermit {
        address account;
        address to;
        uint256 amount;
        uint256 feeBps;
        uint256 nonce;
        uint256 deadline;
    }

    struct TokenFeePermit {
        address account;
        address token;
        address to;
        uint256 amount;
        uint256 feeBps;
        uint256 nonce;
        uint256 deadline;
    }
    // Errors
    error ZeroAddress();
    error FeePercentageTooHigh(uint256 percentageBps);
    error MaximumFeePercentageTooHigh(uint256 percentageBps);
    error SystemFeeExceedsMaximum(uint256 systemFeeBps, uint256 maximumFeeBps);
    error InvalidPermit();
    error InvalidRecipient(address recipient);
    error InsufficientBalance(uint256 required, uint256 available);
    error InsufficientTokenAllowance(uint256 required, uint256 allowance);
    error FeeTransferFailed(address treasury, uint256 amount);
    error TransferFailed(address to, uint256 amount);
    error PermitExpired(uint256 deadline, uint256 currentTime);
    error NonceUsed(uint256 nonce);
    error CustomFeeExceedsMaximum(uint256 customFeeBps, uint256 maximumFeeBps);
    error InvalidAmount(uint256 amount);
    error IncorrectMsgValue(uint256 expected, uint256 actual);

    // Events
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FeeConfigUpdated(uint256 newPercentageBps, uint256 newMaximumPercentageBps);
    event FeeSignerUpdated(address indexed oldSigner, address indexed newSigner);
    event FeeCollected(address indexed treasury, uint256 feeAmount, uint256 transferAmount);
    event ETHTransferred(address indexed to, uint256 amount, uint256 feeAmount, bool isCustomFee);
    event TokenTransferred(address indexed token, address indexed to, uint256 amount, uint256 feeAmount, bool isCustomFee);
    /**
     * @notice Address receiving collected fees.
     * @return treasuryAddress The treasury address
     */
    function treasury() external view returns (address treasuryAddress);

    /**
     * @notice Default system fee in basis points (100 = 1%).
     * @return bps The default fee basis points
     */
    function systemFeePercentage() external view returns (uint256 bps);

    /**
     * @notice Maximum allowed fee in basis points.
     * @return bps The maximum fee basis points
     */
    function maximumFeePercentage() external view returns (uint256 bps);

    

    /**
     * @notice Transfer ETH using an EIP-712 permit signed by the fee signer.
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
    ) external payable;

    /**
     * @notice Transfer ERC20 tokens using an EIP-712 permit signed by the fee signer.
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
    ) external;

    /**
     * @notice Returns the EIP-712 domain separator used for permits.
     * @return separator The domain separator
     */
    function getDomainSeparator() external view returns (bytes32 separator);

    /**
     * @notice Address authorized to sign fee permits.
     * @return signer The fee signer address
     */
    function feeSigner() external view returns (address signer);
}
