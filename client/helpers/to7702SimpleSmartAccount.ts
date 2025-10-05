// make7702SimpleSmartAccount.ts
import { encodeFunctionData, decodeFunctionData, type Address, type Hex, createPublicClient, http } from "viem";
import type { LocalAccount } from "viem/accounts";
import type { PublicClient } from "viem";
import {
  toSmartAccount,
  getUserOperationTypedData,
  entryPoint08Abi,
  entryPoint08Address,
  type SmartAccount,
} from "viem/account-abstraction";

/** ABIs for execute/executeBatch, like in your snippet */
const executeSingleAbi = [
  {
    inputs: [
      { internalType: "address", name: "dest", type: "address" },
      { internalType: "uint256", name: "value", type: "uint256" },
      { internalType: "bytes", name: "func", type: "bytes" },
    ],
    name: "execute",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

const executeBatch08Abi = [
  {
    type: "function",
    name: "executeBatch",
    inputs: [
      {
        name: "calls",
        type: "tuple[]",
        internalType: "struct BaseAccount.Call[]",
        components: [
          { name: "target", type: "address", internalType: "address" },
          { name: "value", type: "uint256", internalType: "uint256" },
          { name: "data", type: "bytes", internalType: "bytes" },
        ],
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

/** Minimal getNonce for EntryPoint v0.8 (key = 0 by default) */
async function getEpNonceV08(
  client: PublicClient,
  ep: Address,
  sender: Address,
  key = 0n
) {
  // getNonce(address sender, uint192 key) returns (uint256)
  const nonce = await client.readContract({
    address: ep,
    abi: entryPoint08Abi,
    functionName: "getNonce",
    args: [sender, key],
  });
  return nonce as bigint;
}

/** Pure, manual version of to7702SimpleSmartAccount */
export async function make7702SimpleSmartAccount(params: {
  client: PublicClient;
  owner: LocalAccount; // you already have this from privateKeyToAccount
  accountLogicAddress?: Address; // optional override
}): Promise<SmartAccount> {
  const { client, owner } = params;
  const accountLogicAddress: Address =
    (params.accountLogicAddress as Address) ??
    // same default from your code
    ("0xe6Cae83BdE06E4c305530e199D7217f42808555B" as Address);

  // For 7702 path, account address IS the owner's EOA address.
  const accountAddress = owner.address as Address;

  // EntryPoint v0.8 (abi+address) – same as your helper used when eip7702=true
  const entryPoint = {
    address: entryPoint08Address as Address,
    abi: entryPoint08Abi,
    version: "0.8" as const,
  };

  // No factory/initCode in 7702 path.
  const getFactoryArgs = async () => ({
    factory: undefined,
    factoryData: undefined,
  });

  // Build the SmartAccount object manually.
  const smart = await toSmartAccount({
    client,
    entryPoint,
    getFactoryArgs,
    // 7702-specific hooks:
    extend: { implementation: accountLogicAddress },
    authorization: {
      address: accountLogicAddress,
      account: owner as any, // Type assertion to bypass strict type checking
    },
    async getAddress() {
      return accountAddress;
    },
    async encodeCalls(calls) {
      if (!calls?.length) throw new Error("No calls to encode");

      if (calls.length === 1) {
        const [c] = calls;
        return encodeFunctionData({
          abi: executeSingleAbi,
          functionName: "execute",
          args: [c.to, c.value ?? 0n, (c.data ?? "0x") as Hex],
        });
      }

      // batch (EP 0.8 struct[] Call)
      return encodeFunctionData({
        abi: executeBatch08Abi,
        functionName: "executeBatch",
        args: [
          calls.map((a) => ({
            target: a.to,
            value: a.value ?? 0n,
            data: (a.data ?? "0x") as Hex,
          })),
        ],
      });
    },
    async decodeCalls(callData) {
      // Try decode batch first
      try {
        const decoded = decodeFunctionData({
          abi: executeBatch08Abi,
          data: callData as Hex,
        });
        return (decoded.args[0] as any[]).map((c) => ({
          to: c.target as Address,
          value: c.value as bigint,
          data: c.data as Hex,
        }));
      } catch {
        // Fallback to single
        const single = decodeFunctionData({
          abi: executeSingleAbi,
          data: callData as Hex,
        });
        return [
          {
            to: single.args[0] as Address,
            value: single.args[1] as bigint,
            data: single.args[2] as Hex,
          },
        ];
      }
    },
    async getNonce(args) {
      const key = args?.key ?? 0n;
      return getEpNonceV08(
        client,
        entryPoint.address,
        await this.getAddress(),
        key
      );
    },
    async getStubSignature() {
      return "0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c";
    },
    async sign({ hash }) {
      // viem SmartAccount contract-style sign wrapper
      return this.signMessage({ message: hash });
    },
    // 1271 is intentionally not implemented – matches your original behavior
    signMessage: async () => {
      throw new Error("Simple account isn't 1271 compliant");
    },
    signTypedData: async () => {
      throw new Error("Simple account isn't 1271 compliant");
    },
    async signUserOperation(userOpInput) {
      // EP v0.8 uses EIP-712 typed data signing.
      const chainId = client.chain?.id ?? 11155111; // Sepolia chain ID as fallback
      const typedData = getUserOperationTypedData({
        chainId,
        entryPointAddress: entryPoint.address,
        userOperation: {
          ...userOpInput,
          sender: userOpInput.sender ?? (await this.getAddress()),
          signature: "0x",
        },
      });
      return owner.signTypedData(typedData);
    },
  });

  return smart;
}
