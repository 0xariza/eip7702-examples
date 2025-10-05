import { ethers } from "ethers";
import { createAuthorization } from "../helpers/createAuthorization";
import { contractABI } from "./abi";

/**
 * Send ETH using EIP-7702 Type 4 transaction by invoking the account's execute with a single call.
 * @param signer Wallet that owns the EOA (and will authorize the 7702 tx)
 * @param to Recipient address
 * @param amountEth Amount of ETH to send, as a string (e.g. "0.01")
 */
export const transferEth7702 = async (
  signer: ethers.Wallet,
  to: string,
  amountEth: string
) => {
  const currentNonce = await signer.getNonce();
  console.log("Current nonce for signer:", currentNonce);

  // Create authorization with incremented nonce for same-wallet transactions (7702 requirement)
  const auth = await createAuthorization(signer, currentNonce + 1);

  console.log("starting ETH transfer via 7702");

  // Single call: send ETH to recipient, empty data
  const value = ethers.parseEther(amountEth);
  const ethTransferCall: [string, bigint, string] = [to, value, "0x"];

  const batchedCall = {
    calls: [ethTransferCall],
    revertOnFailure: true,
  };

  // The account code is active for the duration of the Type 4 tx, so target is the signer's address
  const account = new ethers.Contract(signer.address, contractABI, signer);

  const tx = await account["execute(((address,uint256,bytes)[],bool))"](batchedCall, {
    type: 4,
    authorizationList: [auth],
    // value is not set here; value flows from the call struct handled by the account
  });
  console.log("transaction sent:", tx.hash);

  const receipt = await tx.wait();
  console.log("Receipt:", receipt);

  return receipt;
};




