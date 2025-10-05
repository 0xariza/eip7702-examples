import { ethers } from "ethers";

/**
 * Fee Permit Generator for VaulteraSmartAccount using ethers.js
 * This module handles the generation of EIP-712 fee permits for backend authorization
 */

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

export class FeePermitGeneratorEthers {
  private feeSigner: ethers.Wallet;
  private chainId: number;
  private contractAddress: string;

  constructor(feeSignerPrivateKey: string, chainId: number, feeManagerAddress: string) {
    this.feeSigner = new ethers.Wallet(feeSignerPrivateKey);
    this.chainId = chainId;
    this.contractAddress = feeManagerAddress;
  }

  /**
   * Generate ETH transfer fee permit using ethers.js signTypedData
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

    // Define the EIP-712 domain
    const domain = {
      name: "FeeManager",
      version: "1",
      chainId: this.chainId,
      verifyingContract: this.contractAddress
    };

    // Define the EIP-712 types
    const types = {
      FeePermit: [
        { name: "account", type: "address" },
        { name: "to", type: "address" },
        { name: "amount", type: "uint256" },
        { name: "feeBps", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" }
      ]
    };

    // Sign the typed data
    const signature = await this.feeSigner.signTypedData(domain, types, permit);

    return { permit, signature };
  }

  /**
   * Generate ERC20 token transfer fee permit using ethers.js signTypedData
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

    // Define the EIP-712 domain
    const domain = {
      name: "FeeManager",
      version: "1",
      chainId: this.chainId,
      verifyingContract: this.contractAddress
    };

    // Define the EIP-712 types
    const types = {
      TokenFeePermit: [
        { name: "account", type: "address" },
        { name: "token", type: "address" },
        { name: "to", type: "address" },
        { name: "amount", type: "uint256" },
        { name: "feeBps", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" }
      ]
    };

    // Sign the typed data
    const signature = await this.feeSigner.signTypedData(domain, types, permit);

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
export async function createFeePermitForUserEthers(
  userAccount: string,
  recipient: string,
  amount: bigint,
  customFeeBps: number,
  feeSignerPrivateKey: string,
  chainId: number,
  contractAddress: string
) {
  const generator = new FeePermitGeneratorEthers(feeSignerPrivateKey, chainId, contractAddress);
  
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
export async function createTokenFeePermitForUserEthers(
  userAccount: string,
  tokenAddress: string,
  recipient: string,
  amount: bigint,
  customFeeBps: number,
  feeSignerPrivateKey: string,
  chainId: number,
  contractAddress: string
) {
  const generator = new FeePermitGeneratorEthers(feeSignerPrivateKey, chainId, contractAddress);
  
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
