import dotenv from "dotenv";
import { http, createPublicClient, parseEther, formatEther, encodeFunctionData, keccak256 } from "viem";
import { sepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

import { make7702SimpleSmartAccount } from "../helpers/to7702SimpleSmartAccount";
import { createSmartAccountClient } from "../helpers/createSmartAccountClient";
import { recipient1, recipient2 } from "../consts";

dotenv.config();

// Contract addresses
const VAULTERA_SMART_ACCOUNT = "0xDB2Dc9d1076b5560B9a160145613cbd0CD0550C4" as const;
const FEE_MANAGER = "0xF77f34d881883054aa0478Ae71F91273f8D997B7" as const;

// VaulteraSmartAccount ABI - only the functions we need
const vaulteraSmartAccountAbi = [
  {
    inputs: [
      { internalType: "address", name: "to", type: "address" },
      { internalType: "uint256", name: "amount", type: "uint256" },
      { internalType: "uint256", name: "feeBps", type: "uint256" },
      { internalType: "uint256", name: "nonce", type: "uint256" },
      { internalType: "uint256", name: "deadline", type: "uint256" },
      { internalType: "bytes", name: "signature", type: "bytes" }
    ],
    name: "transferETH",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [],
    name: "getDomainSeparator",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function"
  }
] as const;

// Minimal FeeManager ABI fragments we need
const feeManagerAbi = [
  {
    inputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    name: "usedNonces",
    outputs: [{ internalType: "bool", name: "", type: "bool" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "getDomainSeparator",
    outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
    stateMutability: "view",
    type: "function"
  }
] as const;

// EIP-712 Types
const FEE_PERMIT_TYPES = {
  FeePermit: [
    { name: 'account', type: 'address' },
    { name: 'to', type: 'address' },
    { name: 'amount', type: 'uint256' },
    { name: 'feeBps', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' }
  ]
} as const;

const DOMAIN_TYPE = {
  EIP712Domain: [
    { name: 'name', type: 'string' },
    { name: 'version', type: 'string' },
    { name: 'chainId', type: 'uint256' },
    { name: 'verifyingContract', type: 'address' }
  ]
} as const;

// Generate a unique nonce (you might want to use a more sophisticated approach)
function generateNonce(): bigint {
  return BigInt(Date.now() + Math.floor(Math.random() * 1000000));
}

export async function transferETHWithPermit() {
  const privateKey = process.env.PRIVATE_KEY as `0x${string}`;
  const feeSignerPrivateKey = process.env.FEE_SIGNER_PRIVATE_KEY as `0x${string}`;
  
  if (!feeSignerPrivateKey) {
    throw new Error("FEE_SIGNER_PRIVATE_KEY environment variable is required");
  }

  const eoa7702 = privateKeyToAccount(privateKey);
  const feeSigner = privateKeyToAccount(feeSignerPrivateKey);

  const client = createPublicClient({
    chain: sepolia,
    transport: http("https://ethereum-sepolia-rpc.publicnode.com"),
  });

  // Create 7702 smart account
  const vaulteraAccount = await make7702SimpleSmartAccount({
    client,
    owner: eoa7702,
    accountLogicAddress: VAULTERA_SMART_ACCOUNT,
  });

  const smartAccountClient = createSmartAccountClient({
    client,
    chain: sepolia,
    account: vaulteraAccount,
    bundlerTransport: http(
      `https://api.pimlico.io/v2/11155111/rpc?apikey=${process.env.PIMLICO_API_KEY}`
    ),
  });

  // Check current balance
  const accountBalance = await client.getBalance({
    address: vaulteraAccount.address
  });

  console.log("=== VaulteraSmartAccount Transfer with Permit ===");
  console.log(`Account Address: ${vaulteraAccount.address}`);
  console.log(`Current Balance: ${formatEther(accountBalance)} ETH`);
  console.log(`Fee Signer Address: ${feeSigner.address}`);

  // Define transfer parameters
  const transferAmount = parseEther("0.001"); // 0.001 ETH
  const feeBps = 250n; // 2.5% fee (250 basis points)
  const nonce = generateNonce();
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour from now

  console.log(`\nTransfer Amount: ${formatEther(transferAmount)} ETH`);
  console.log(`Fee: ${Number(feeBps) / 100}% (${feeBps} basis points)`);
  console.log(`Recipient: ${recipient1}`);
  console.log(`Nonce: ${nonce}`);
  console.log(`Deadline: ${new Date(Number(deadline) * 1000).toISOString()}`);

  // Check if nonce is already used (via FeeManager)
  try {
    const isNonceUsed = await client.readContract({
      address: FEE_MANAGER,
      abi: feeManagerAbi,
      functionName: "usedNonces",
      args: [nonce]
    });

    if (isNonceUsed) {
      console.log("❌ Nonce already used, generating new one...");
      const newNonce = generateNonce();
      console.log(`New nonce: ${newNonce}`);
    }
  } catch (error) {
    console.log("Could not check nonce status, proceeding...");
  }

  // Estimate total required amount (including fees) client-side
  const estimatedFeeAmount = (transferAmount * feeBps) / 10000n;
  const estimatedTotalRequired = transferAmount + estimatedFeeAmount;
  console.log(`\n=== Fee Estimation ===`);
  console.log(`Fee Amount: ${formatEther(estimatedFeeAmount)} ETH`);
  console.log(`Total Required: ${formatEther(estimatedTotalRequired)} ETH`);
  if (accountBalance < estimatedTotalRequired) {
    console.log(`❌ Insufficient balance! Need ${formatEther(estimatedTotalRequired)} ETH, have ${formatEther(accountBalance)} ETH`);
    return;
  }

  // Get domain separator
  let domainSeparator: `0x${string}`;
  try {
    domainSeparator = await client.readContract({
      address: VAULTERA_SMART_ACCOUNT,
      abi: vaulteraSmartAccountAbi,
      functionName: "getDomainSeparator"
    }) as `0x${string}`;
    console.log(`Domain Separator: ${domainSeparator}`);
  } catch (error) {
    console.log("Could not get domain separator");
  }

  // Create the permit message
  const permitMessage = {
    account: vaulteraAccount.address,
    to: recipient1 as `0x${string}`,
    amount: transferAmount,
    feeBps: feeBps,
    nonce: nonce,
    deadline: deadline
  };

  console.log("\n=== Permit Message ===");
  console.log(JSON.stringify(permitMessage, (key, value) =>
    typeof value === 'bigint' ? value.toString() : value
  , 2));

  // Sign the permit using EIP-712
  const signature = await feeSigner.signTypedData({
    domain: {
      name: 'FeeManager',
      version: '1',
      chainId: sepolia.id,
      verifyingContract: FEE_MANAGER
    },
    types: FEE_PERMIT_TYPES,
    primaryType: 'FeePermit',
    message: permitMessage
  });

  console.log(`\n=== Signature ===`);
  console.log(`Signature: ${signature}`);

  console.log("\n=== Executing Transaction ===");

  try {
    // Calculate total value to be spent from account balance (transfer + fee)
    const feeAmount = (transferAmount * feeBps) / 10000n;
    const totalValue = transferAmount + feeAmount;

    console.log(`Spending ${formatEther(totalValue)} ETH from account (${formatEther(transferAmount)} transfer + ${formatEther(feeAmount)} fee)`);

    // For EIP-7702, call the function directly on the account (not through calls array)
    const transactionHash = await smartAccountClient.sendTransaction({
      to: vaulteraAccount.address, // Call on the account itself since it now has the contract code
      value: 0n,
      data: encodeFunctionData({
        abi: vaulteraSmartAccountAbi,
        functionName: 'transferETH',
        args: [
          recipient1 as `0x${string}`,
          transferAmount,
          feeBps,
          nonce,
          deadline,
          signature
        ]
      }),
      authorization: await eoa7702.signAuthorization({
        address: VAULTERA_SMART_ACCOUNT,
        chainId: sepolia.id,
        nonce: await client.getTransactionCount({
          address: eoa7702.address,
        }),
      }),
    });

    console.log("✅ Transaction submitted!");
    console.log("Transaction hash:", transactionHash);
    console.log(`\nView on Sepolia Etherscan: https://sepolia.etherscan.io/tx/${transactionHash}`);
    
    // Wait for confirmation
    console.log("\n⏳ Waiting for confirmation...");
    const receipt = await client.waitForTransactionReceipt({ hash: transactionHash });
    
    if (receipt.status === 'success') {
      console.log("✅ Transaction confirmed!");
      console.log(`Gas used: ${receipt.gasUsed}`);
    } else {
      console.log("❌ Transaction failed!");
    }

  } catch (error) {
    console.error("❌ Transaction failed:", error);
    
    // Try to provide more helpful error information
    if (error instanceof Error) {
      if (error.message.includes('InsufficientBalance')) {
        console.log("💡 The account doesn't have enough ETH for the transfer and fees");
      } else if (error.message.includes('InvalidPermit')) {
        console.log("💡 The permit signature is invalid - check the fee signer and message format");
      } else if (error.message.includes('PermitExpired')) {
        console.log("💡 The permit has expired - try with a longer deadline");
      } else if (error.message.includes('NonceUsed')) {
        console.log("💡 The nonce has already been used - generate a new one");
      }
    }
  }
}

// Run the script
if (require.main === module) {
  transferETHWithPermit().catch(console.error);
}