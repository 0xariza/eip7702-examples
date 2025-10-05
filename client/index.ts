import dotenv from "dotenv";
dotenv.config();

import { pimlico } from "./transactions/pimlico";
import { initializeSigners } from "./helpers/initializeSigners";

async function sendEIP7702Transactions() {
  try {
    // Initialize signers and get initial balances
    const { provider, signer } = await initializeSigners();

    // Check delegation status before starting
    // await checkDelegationStatus(provider, signer.address);

    // // Execute transactions
    // const receipt = await approveAndLendInAave(signer);

    // console.log("\n=== SUCCESS ===");

    // await revokeDelegation(signer);

    // const receipt = await sendEthTransactionsUsingPimlico();

    const receipt = await pimlico();

    return { receipt };
  } catch (error) {
    console.error("Error in EIP-7702 transactions:", error);
    throw error;
  }
}

// Execute the main function
sendEIP7702Transactions()
  .then(() => {
    console.log("Process completed successfully.");
  })
  .catch((error) => {
    console.error("Failed to send EIP-7702 transactions:", error);
  });
