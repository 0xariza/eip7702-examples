# eip7702-defi-kit
## createSmartAccountClient — Bundler-aware Smart Account Client

Purpose
- Build a Viem client pre-wired for ERC-4337 Smart Accounts. It mounts a bundler transport, optional execution client, optional paymaster hooks, and extends the client with:
  - Bundler actions (send user operations, wait for receipts, etc.)
  - Smart Account actions: `sendTransaction`, `writeContract`, `signMessage`, `signTypedData`.

Definition
```ts
import { createSmartAccountClient } from "./helpers/createSmartAccountClient";
```

Signature
```ts
export function createSmartAccountClient<
  transport extends Transport,
  chain extends Chain | undefined = undefined,
  account extends SmartAccount | undefined = undefined,
  client extends Client | undefined = undefined,
  rpcSchema extends RpcSchema | undefined = undefined
>(
  parameters: SmartAccountClientConfig<
    transport,
    chain,
    account,
    client,
    rpcSchema
  >
): SmartAccountClient<transport, chain, account, client, rpcSchema>;
```

Inputs (SmartAccountClientConfig)
- Required
  - `bundlerTransport`: Viem `Transport` to your Bundler.
- Optional
  - `account`: `SmartAccount` instance.
  - `chain`: Target chain (defaults to `client?.chain`).
  - `client`: Execution RPC `Client` for non-bundler reads/writes.
  - `rpcSchema`, `name`, `key`, `cacheTime`, `pollingInterval`.
  - `paymaster`: `true` or `{ getPaymasterData?, getPaymasterStubData? }`.
  - `paymasterContext`: Arbitrary context object, passed to paymaster hooks.
  - `userOperation`
    - `estimateFeesPerGas({ bundlerClient, account, userOperation })`
    - `prepareUserOperation(bundlerClient, args)` — override full UO preparation.

Output
- `SmartAccountClient` (Viem Client extended with Bundler & Smart Account actions)
  - RPC schema: `[...BundlerRpcSchema, ...rpcSchema?]`
  - Methods: Bundler actions + `sendTransaction`, `writeContract`, `signMessage`, `signTypedData`
  - Extra fields: `client`, `paymaster`, `paymasterContext`, `userOperation`

Under the Hood
- Creates a base Viem client via `createClient` with:
  - `transport: bundlerTransport`
  - `chain: parameters.chain ?? client_?.chain`
  - identifiers: `key` (default: "bundler"), `name` (default: "Bundler Client"), `type: "bundlerClient"`
- Attaches pass-through fields on the instance: `client`, `paymaster`, `paymasterContext`, `userOperation`.
- Extends with actions:
  - If `userOperation.prepareUserOperation` is present:
    - Extend with `bundlerActions` → inject custom `prepareUserOperation` → extend again with `bundlerActions` and re-inject → extend with `smartAccountActions`.
    - Ensures your override consistently shadows any default `prepareUserOperation` from bundler extensions.
  - Else: extend with `bundlerActions` then `smartAccountActions`.

Added Smart Account Actions
- `sendTransaction(args)`
  - If `to` is provided: converts to a single-call UserOperation (`calls = [{ to, value: value ?? 0n, data: data ?? "0x" }]`).
  - Sends via bundler `sendUserOperation`, waits for `waitForUserOperationReceipt`, returns `receipt.transactionHash`.
  - Accepts prebuilt `SendUserOperationParameters` as well (forwarded directly).
- `writeContract({ address, abi, functionName, args, ... })`
  - Encodes calldata with `encodeFunctionData`, then delegates to `sendTransaction` with `to: address` & `data`.
- `signMessage({ message })`
  - Resolves `account` (Smart Account) from client/args, throws if missing, then `account.signMessage({ message })` (EIP-191).
- `signTypedData({ domain, types, primaryType, message })`
  - Resolves `account`, derives `EIP712Domain` types, `validateTypedData`, then `account.signTypedData(...)`.

Bundler & Paymaster Integration
- All UO interactions go through `bundlerTransport` using Viem `bundlerActions` (submit UOs, estimate fees, wait for receipts).
- `paymaster` hooks are available to inject sponsorship/stub data during prepare/send phases; `paymasterContext` is forwarded.
- Custom `prepareUserOperation` allows complete control of the UO build pipeline.

prepareUserOperation (Override) — Lifecycle & Contract
- Purpose: Intercept and fully control how a UserOperation is constructed before signing/sending.
- Signature (as provided in config):
  - `prepareUserOperation: (bundlerClient, args) => Promise<PreparedUserOperation>`
    - `bundlerClient`: the extended client instance with Bundler actions available.
    - `args`: `PrepareUserOperationParameters` (includes account, calls, fee options, paymaster, etc.).
    - Returns a prepared UO object that will be signed/sent downstream.
- Invocation points:
  - When you call actions that create/send a UO (e.g., `sendTransaction`, `writeContract`, or direct Bundler actions), the client will route through `prepareUserOperation` if provided.
- Double-extension behavior:
  - The client gets extended with Bundler actions, then your override is attached, then Bundler actions are extended again and your override is reattached. This guarantees your custom `prepareUserOperation` shadows any default one that Bundler actions might inject.
- Typical responsibilities inside an override:
  - Assemble `calls` and normalize calldata.
  - Compute/override `nonce`.
  - Fetch/merge fee data (optionally via `estimateFeesPerGas`).
  - Integrate paymaster sponsorship (`getPaymasterData`) and handle `paymasterContext`.
  - Return a fully formed `UserOperationRequest` ready for signing/sending.

Errors & Edge Cases
- `AccountNotFoundError` when `account` is missing for `sendTransaction`, `signMessage`, `signTypedData`.
- `nonce` is coerced to `BigInt` when provided in transaction-style sends.
- `to` is required for transaction-style sends; otherwise pass a full UO.

Examples
```ts
import { http } from "viem";
import { createSmartAccountClient } from "./helpers/createSmartAccountClient";

const bundler = http("https://your-bundler");
const client = createSmartAccountClient({
  account: /* SmartAccount */ undefined as any,
  chain: /* Chain */ undefined as any,
  bundlerTransport: bundler,
});

const txHash = await client.sendTransaction({ to: "0x...", value: 0n });
```

```ts
// With Paymaster & Custom UO Prep
const client = createSmartAccountClient({
  account,
  chain,
  bundlerTransport: http(bundlerUrl),
  paymaster: {
    getPaymasterData: async ({ userOperation }) => ({ /* ... */ }),
    getPaymasterStubData: async ({ userOperation }) => ({ /* ... */ }),
  },
  paymasterContext: { sponsor: "myPaymaster" },
  userOperation: {
    estimateFeesPerGas: async ({ bundlerClient, account, userOperation }) => ({
      maxFeePerGas: 1n,
      maxPriorityFeePerGas: 1n,
    }),
    prepareUserOperation: async (bundlerClient, args) => {
      // Build & return a fully prepared UO
      return args as any;
    },
  },
});
```

# installation

npm install -g typescript tsx

npm install

# run
tsx indes.ts
