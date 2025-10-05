import { keccak256, toHex } from "viem";
import { privateKeyToAccount } from "viem/accounts";

/**
 * Fee Permit Generator for VaulteraSmartAccount
 * This module handles the generation of EIP-712 fee permits for backend authorization
 */

// EIP-712 Domain and Type definitions (must match FeeManager contract)
const DOMAIN_TYPEHASH = keccak256(
  toHex("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
);

const FEE_PERMIT_TYPEHASH = keccak256(
  toHex("FeePermit(address account,address to,uint256 amount,uint256 feeBps,uint256 nonce,uint256 deadline)")
);

const TOKEN_FEE_PERMIT_TYPEHASH = keccak256(
  toHex("TokenFeePermit(address account,address token,address to,uint256 amount,uint256 feeBps,uint256 nonce,uint256 deadline)")
);

export interface FeePermitData {
  account: string;
  to: string;
  amount: bigint;
  feeBps: number;
  nonce: bigint;
  deadline: bigint;
}

export interface TokenFeePermitData {
  account: string;
  token: string;
  to: string;
  amount: bigint;
  feeBps: number;
  nonce: bigint;
  deadline: bigint;
}

export class FeePermitGenerator {
  private feeSigner: `0x${string}`;
  private chainId: number;
  private contractAddress: string;

  constructor(feeSignerPrivateKey: string, chainId: number, feeManagerAddress: string) {
    this.feeSigner = privateKeyToAccount(feeSignerPrivateKey as `0x${string}`).address;
    this.chainId = chainId;
    this.contractAddress = feeManagerAddress; // Now points to FeeManager contract
  }

  /**
   * Generate domain separator for EIP-712
   */
  private getDomainSeparator(): string {
    return keccak256(
      toHex(
        `EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)${keccak256(toHex("FeeManager"))}${keccak256(toHex("1"))}${this.chainId.toString(16).padStart(64, '0')}${this.contractAddress.slice(2).padStart(64, '0')}`
      )
    );
  }

  /**
   * Generate ETH transfer fee permit
   */
  async generateETHFeePermit(
    accountAddress: string,
    to: string,
    amount: bigint,
    feeBps: number,
    nonce: bigint,
    deadline: bigint
  ): Promise<{ permit: FeePermitData; signature: string }> {
    const permit: FeePermitData = {
      account: accountAddress,
      to,
      amount,
      feeBps,
      nonce,
      deadline
    };

    // Hash the permit data
    const permitHash = keccak256(
      toHex(
        `FeePermit(address account,address to,uint256 amount,uint256 feeBps,uint256 nonce,uint256 deadline)${accountAddress.slice(2).padStart(64, '0')}${to.slice(2).padStart(64, '0')}${amount.toString(16).padStart(64, '0')}${feeBps.toString(16).padStart(64, '0')}${nonce.toString(16).padStart(64, '0')}${deadline.toString(16).padStart(64, '0')}`
      )
    );

    // Create the final digest
    const digest = keccak256(
      toHex(`\x19\x01${this.getDomainSeparator().slice(2)}${permitHash.slice(2)}`)
    );

    // Sign with the fee signer's private key
    const feeSignerAccount = privateKeyToAccount(process.env.FEE_SIGNER_PRIVATE_KEY as `0x${string}`);
    const signature = await feeSignerAccount.signMessage({ message: { raw: digest } });

    return { permit, signature };
  }

  /**
   * Generate ERC20 token transfer fee permit
   */
  async generateTokenFeePermit(
    accountAddress: string,
    token: string,
    to: string,
    amount: bigint,
    feeBps: number,
    nonce: bigint,
    deadline: bigint
  ): Promise<{ permit: TokenFeePermitData; signature: string }> {
    const permit: TokenFeePermitData = {
      account: accountAddress,
      token,
      to,
      amount,
      feeBps,
      nonce,
      deadline
    };

    // Hash the permit data
    const permitHash = keccak256(
      toHex(
        `TokenFeePermit(address account,address token,address to,uint256 amount,uint256 feeBps,uint256 nonce,uint256 deadline)${accountAddress.slice(2).padStart(64, '0')}${token.slice(2).padStart(64, '0')}${to.slice(2).padStart(64, '0')}${amount.toString(16).padStart(64, '0')}${feeBps.toString(16).padStart(64, '0')}${nonce.toString(16).padStart(64, '0')}${deadline.toString(16).padStart(64, '0')}`
      )
    );

    // Create the final digest
    const digest = keccak256(
      toHex(`\x19\x01${this.getDomainSeparator().slice(2)}${permitHash.slice(2)}`)
    );

    // Sign with the fee signer's private key
    const feeSignerAccount = privateKeyToAccount(process.env.FEE_SIGNER_PRIVATE_KEY as `0x${string}`);
    const signature = await feeSignerAccount.signMessage({ message: { raw: digest } });

    return { permit, signature };
  }

  /**
   * Generate a random nonce for replay protection
   */
  generateNonce(): bigint {
    return BigInt(Math.floor(Math.random() * Number.MAX_SAFE_INTEGER));
  }

  /**
   * Generate deadline timestamp (default 1 hour from now)
   */
  generateDeadline(hoursFromNow: number = 1): bigint {
    return BigInt(Math.floor(Date.now() / 1000) + (hoursFromNow * 3600));
  }
}

// Example usage for your backend
export async function createFeePermitForUser(
  userAccount: string,
  recipient: string,
  amount: bigint,
  customFeeBps: number,
  feeSignerPrivateKey: string,
  chainId: number,
  contractAddress: string
) {
  const generator = new FeePermitGenerator(feeSignerPrivateKey, chainId, contractAddress);
  
  const nonce = generator.generateNonce();
  const deadline = generator.generateDeadline(1); // 1 hour from now
  
  return await generator.generateETHFeePermit(
    userAccount,
    recipient,
    amount,
    customFeeBps,
    nonce,
    deadline
  );
}

// Example for token transfers
export async function createTokenFeePermitForUser(
  userAccount: string,
  tokenAddress: string,
  recipient: string,
  amount: bigint,
  customFeeBps: number,
  feeSignerPrivateKey: string,
  chainId: number,
  contractAddress: string
) {
  const generator = new FeePermitGenerator(feeSignerPrivateKey, chainId, contractAddress);
  
  const nonce = generator.generateNonce();
  const deadline = generator.generateDeadline(1); // 1 hour from now
  
  return await generator.generateTokenFeePermit(
    userAccount,
    tokenAddress,
    recipient,
    amount,
    customFeeBps,
    nonce,
    deadline
  );
}
