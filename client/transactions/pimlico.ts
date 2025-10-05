import dotenv from "dotenv";
import { http, createPublicClient, zeroAddress, parseEther, formatEther } from "viem";
import { sepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

import { make7702SimpleSmartAccount } from "../helpers/to7702SimpleSmartAccount";
import { createSmartAccountClient } from "../helpers/createSmartAccountClient";
import { recipient1, recipient2 } from "../consts";

dotenv.config();

// Treasury7702Account ABI for fee estimation
const treasury7702Abi = [
  {
    inputs: [{ internalType: "uint256", name: "transactionValue", type: "uint256" }],
    name: "estimateSystemFee",
    outputs: [
      { internalType: "uint256", name: "systemFee", type: "uint256" },
      { internalType: "uint256", name: "totalRequired", type: "uint256" },
      { internalType: "uint256", name: "effectiveFeeRate", type: "uint256" }
    ],
    stateMutability: "view",
    type: "function"
  }
] as const;

export async function pimlico() {
  const privateKey = process.env.PRIVATE_KEY as `0x${string}`;
  const eoa7702 = privateKeyToAccount(privateKey);

  const client = createPublicClient({
    chain: sepolia,
    transport: http("https://ethereum-sepolia-rpc.publicnode.com"),
  });

  // Your deployed Treasury7702Account address (updated with EIP-7702 fix)
  const treasury7702AccountAddress = "0x368CdC277E8756720f6d599829aa85E679092061" as const;

  // Step 1: Create 7702 smart account using your Treasury contract
  const treasury7702Account = await make7702SimpleSmartAccount({
    client,
    owner: eoa7702,
    accountLogicAddress: treasury7702AccountAddress, // Use your Treasury contract as logic
  });

  const smartAccountClient = createSmartAccountClient({
    client,
    chain: sepolia,
    account: treasury7702Account,
    bundlerTransport: http(
      `https://api.pimlico.io/v2/11155111/rpc?apikey=${process.env.PIMLICO_API_KEY}`
    ),
  });

  // Check current balance first
  const accountBalance = await client.getBalance({
    address: treasury7702AccountAddress
  });

  console.log("=== Treasury 7702 Account Two Transfer ===");
  console.log(`Account Address: ${treasury7702AccountAddress}`);
  console.log(`Current Balance: ${formatEther(accountBalance)} ETH`);

  // Calculate small amounts based on available balance
  // Reserve some ETH for fees, use 80% of balance for transfers
  const availableForTransfers = (accountBalance * 80n) / 100n; // 80% of balance
  const transfer1Amount = availableForTransfers / 2n; // Split between two transfers
  const transfer2Amount = availableForTransfers / 2n;
  const totalTransferAmount = transfer1Amount + transfer2Amount;

  console.log(`Transfer 1: ${formatEther(transfer1Amount)} ETH to ${recipient1}`);
  console.log(`Transfer 2: ${formatEther(transfer2Amount)} ETH to ${recipient2}`);
  console.log(`Total Transfer Amount: ${formatEther(totalTransferAmount)} ETH`);

  // Estimate fees from the Treasury contract
  try {
    const feeEstimate = await client.readContract({
      address: treasury7702AccountAddress,
      abi: treasury7702Abi,
      functionName: "estimateSystemFee",
      args: [totalTransferAmount]
    });

    console.log("\n=== Fee Estimation ===");
    console.log(`System Fee: ${formatEther(feeEstimate[0])} ETH`);
    console.log(`Total Required: ${formatEther(feeEstimate[1])} ETH`);
    console.log(`Effective Fee Rate: ${feeEstimate[2]} basis points (${Number(feeEstimate[2]) / 100}%)`);

    if (accountBalance < feeEstimate[1]) {
      console.log(`❌ Insufficient balance! Need ${formatEther(feeEstimate[1])} ETH, have ${formatEther(accountBalance)} ETH`);
      console.log(`💡 The account needs more ETH to cover transfers and fees`);
      return;
    }

  } catch (error) {
    console.log("⚠️  Could not estimate fees, proceeding with transaction...");
    console.log("Error:", error);
  }

  console.log("\n=== Executing Transaction ===");

  // Execute two transfers with treasury fee collection
  const transactionHash = await smartAccountClient.sendTransaction({
    calls: [
      {
        to: recipient1,
        value: transfer1Amount,
        data: "0x", // Simple ETH transfer
      },
      {
        to: recipient2,
        value: transfer2Amount,
        data: "0x", // Simple ETH transfer
      },
    ],
    authorization: await eoa7702.signAuthorization({
      address: treasury7702AccountAddress, // Use your Treasury contract address
      chainId: sepolia.id,
      nonce: await client.getTransactionCount({
        address: eoa7702.address,
      }),
    }),
  });

  console.log("✅ Transaction submitted!");
  console.log("Transaction hash:", transactionHash);
  console.log(`\nView on Sepolia Etherscan: https://sepolia.etherscan.io/tx/${transactionHash}`);
}

