import { ethers } from "ethers";
import { createAuthorization } from "../helpers/createAuthorization";
import { aaveLinkPoolAddress, erc20Token } from "../consts";
import { contractABI } from "./abi";

/**
 * Lend tokens in Aave using EIP-7702 Type 4 transaction by invoking the account's execute with batched calls.
 * @param signer Wallet that owns the EOA (and will authorize the 7702 tx)
 * @param amount Amount of tokens to lend, as a string (e.g. "1.0")
 * @param decimals Token decimals (default: 18)
 */
export const aaveLend7702 = async (
  signer: ethers.Wallet,
  amount: string,
  decimals: number = 18
) => {
  const currentNonce = await signer.getNonce();
  console.log("Current nonce for signer:", currentNonce);

  // Create authorization with incremented nonce for same-wallet transactions (7702 requirement)
  const auth = await createAuthorization(signer, currentNonce + 1);

  console.log("starting Aave lending via 7702");

  // Approve ERC20 token for Aave pool
  const erc20Abi = ["function approve(address spender, uint256 amount)"];
  const erc20Interface = new ethers.Interface(erc20Abi);

  const spender = aaveLinkPoolAddress;
  const tokenAmount = ethers.parseUnits(amount, decimals);

  const approveCall: [string, bigint, string] = [
    erc20Token, // to
    0n, // value (ETH)
    erc20Interface.encodeFunctionData("approve", [spender, tokenAmount]), // data
  ];

  // Supply tokens to Aave
  const aaveAbi = [
    "function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)",
  ];
  const aaveInterface = new ethers.Interface(aaveAbi);

  const aavePoolAddress = aaveLinkPoolAddress;

  const supplyCall: [string, bigint, string] = [
    aavePoolAddress,
    0n,
    aaveInterface.encodeFunctionData("supply", [
      erc20Token,
      tokenAmount,
      signer.address,
      0,
    ]),
  ];

  const batchedCall = {
    calls: [approveCall, supplyCall],
    revertOnFailure: true,
  };

  // The account code is active for the duration of the Type 4 tx, so target is the signer's address
  const account = new ethers.Contract(signer.address, contractABI, signer);

  const tx = await account["execute(((address,uint256,bytes)[],bool))"](batchedCall, {
    type: 4,
    authorizationList: [auth],
  });
  console.log("transaction sent:", tx.hash);

  const receipt = await tx.wait();
  console.log("Receipt:", receipt);

  return receipt;
};

