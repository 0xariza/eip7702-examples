# Vaultera 7702 Delegator

Permit-driven Fee Manager and Vaultera Smart Account designed for ERC-4337-style flows (and EIP-7702 client usage). Enables ETH and ERC20 transfers with configurable fees authorized via EIP-712 permits.

## Overview

- FeeManager (`src/feeManager`)
  - Collects system or custom fees on ETH and ERC20 transfers
  - All transfers authorized via EIP-712 permits signed by a `feeSigner`
  - Errors and events declared in `IFeeManager`
- VaulteraSmartAccount (`src/vaulteraSmartAccount`)
  - Minimal account integrating with `IFeeManager`
  - Permit-based forwarding: `transferETH` and `transferToken` (permit-style signatures)
  - Public accessor `entryPoint()` returns the configured EntryPoint; private immutable storage under the hood

Key choices:
- Errors and events live in interfaces (`IFeeManager`, `IVaulteraSmartAccount`)
- Solhint-friendly function ordering and NatSpec comments
- Non-permit flows removed for a single, auditable path

## Contracts

- `src/feeManager/IFeeManager.sol` – Interface, structs, errors, events
- `src/feeManager/FeeManager.sol` – Permit-based fee collection (ETH and ERC20)
- `src/vaulteraSmartAccount/IVaulteraSmartAccount.sol` – Interface and errors
- `src/vaulteraSmartAccount/VaulteraSmartAccount.sol` – Smart account integrating FeeManager

### Permit Structs (in `IFeeManager`)
- `FeePermit { account, to, amount, feeBps, nonce, deadline }`
- `TokenFeePermit { account, token, to, amount, feeBps, nonce, deadline }`

### Typehash Helpers (in `FeeManager`)
- `FEE_PERMIT_TYPEHASH()`
- `TOKEN_FEE_PERMIT_TYPEHASH()`
- `getDomainSeparator()`

## Requirements

- Node.js and npm/yarn (for `client/`)
- Foundry (forge)
- Sepolia RPC for deploys/examples

## Setup

Create environment files.

Root `.env`:
```
PRIVATE_KEY=0x...
SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
PIMLICO_API_KEY=
FEE_SIGNER_PRIVATE_KEY=0x...
```

Client `client/.env`:
```
PRIVATE_KEY=0x...
FEE_SIGNER_PRIVATE_KEY=0x...
RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
CHAIN_ID=11155111
PIMLICO_API_KEY=
VAULTERA_SMART_ACCOUNT=
FEE_MANAGER=
```

## Build & Test

```
forge build
forge test -vvv
```

## Deploy (Foundry)

```
forge script script/DeployFeeManager.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
forge script script/DeployVaulteraSmartAccount.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## Client (EIP-7702)

Inside `client/` you can sign EIP-712 fee permits and call `VaulteraSmartAccount.transferETH` / `transferToken` using those permits.

```
cd client
npm install
npm run start
```

## Style & Linting

- Function order per solhint
- NatSpec used across contracts
- Errors/events kept in interfaces

## Security Notes

- Permit-only flows (no direct non-permit transfers)
- Signature, deadline, nonce checks; replay-protected
- Fee caps enforced

## License

MIT
