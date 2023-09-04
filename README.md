# swap-pool 😎

A modular Solidity-based solution handling asset swaps within the [Frak](https://frak.id/) ecosystem. Streamlined, secure, and designed with developers in mind.

## Table of Contents 📑

1. [Features](#features-)
2. [Contract Structure](#contract-structure-)
3. [How It Works](#how-it-works-)
   - [Internal Flash Accounting](#internal-flash-accounting-)
   - [Unified Token Management](#unified-token-management-)
   - [Program](#program-)
   - [Operations](#operations-)
4. [Supported Operations](#supported-operations-)
5. [Installation and Usage](#installation--usage-instructions-)
   - [Prerequisites](#prerequisites)
   - [Building the Contracts](#building-the-contracts)
   - [Testing](#testing)
   - [Coverage Reports](#coverage-reports)
   - [Gas Consumption Snapshots](#gas-consumption-snapshots)
   - [Slither Code Analysis](#slither-code-analysis)
6. [Security Audits](#security-audits-)
7. [Credits & Acknowledgments](#credits--acknowledgments-)
8. [Authors](#authors-)
9. [License](#license-)

## Features 🌟

- **Pool Per Contract Mechanism**: Enhanced flexibility by allowing a dedicated pool for each contract.
- **In-Memory Accounting**: Optimized performance by handling account balances and transactions in memory.
- **EIP-2612 Permit Signature Support**: Integrated support for EIP-2612 permit signatures, enabling better user experience and security.
- **Unified Token Abstraction**: With the new `TokenLib.sol`, seamlessly manage both ERC-20 tokens and native chain tokens using a singular user-defined value type.

## Contract Structure 📜

```plaintext
.
├── MonoPool.sol               - Contract containing a single pool
├── Ops.sol                    - Contains the list of all available operations (Ops)
├── lib
│   ├── AccounterLib.sol       - Library containing the in-memory accounting logic (account changes, get changes, reset changes etc)
│   ├── PoolLib.sol            - Related to all the pool logic (add/rm liquidity, trigger swap)
│   ├── SwapLib.sol            - Library containing the stuff related to swap operation computation
│   └── TokenLib.sol           - Unified token type for ERC-20 and native tokens abstraction
├── encoder
│   ├── DecoderLib.sol         - Helps decode data for each operation
│   └── EncoderLib.sol         - Assists off-chain users to build their program. Not for on-chain use. (Gas inefficient)
```

Always remember: Use `EncoderLib` exclusively in off-chain scenarios for optimal gas efficiency.

## How It Works 🧠

### Internal Flash Accounting 💡

- The pool employs an internal accounting system to keep track of balance changes for two specific tokens, namely `token0` and `token1`, during the course of a transaction block (flash execution). This seamless tracking is possible thanks to the abstraction provided by the `TokenLib.sol`.
- Instead of making changes to the Ethereum state immediately, the contract first tracks net balance changes internally.
- After all operations have been executed, the contract then applies the final net changes to the actual balances of `token0` and `token1` at the end of the transaction block.
- This approach aims to minimize gas usage, as frequent state changes (storage operations) are generally costly in terms of gas.

### Unified Token Management 🪙

- With the new `TokenLib.sol`, the system has a built-in abstraction layer to handle both ERC-20 tokens and native tokens (represented by the address 0).
- This allows for seamless transfers and balance checks for both ERC-20 and native chain tokens.
- Whether interacting with ERC-20's `transfer()` and `balanceOf()` or native chain operations, the underlying logic remains abstracted, reducing complexity and potential errors.

### Program 📜

- Interactions with the pools are facilitated via the `execute(bytes program)` function.
- The "program" is essentially a serialized set of operations and follows a specific structure:
  - Every operation within this program comprises:
    - An 8-bit operation, spanning 1 byte.
    - Data pertaining to the opcode, spanning 'n' bytes.
- This encoding method ensures minimal calldata size, given that each operation might need different data amounts.

### Operations 🔧

- An 8-bit operation specifier contains two parts:
  - The first 4 bits (half) represent the operation ID (Op Code).
  - The latter 4 bits represent flags.
- Thus, there's the potential for up to 16 primary operations. Each can interpret 4 additional flags.
- Parameters are always packed tightly.
- Encoding of individual operations can be found in the `EncoderLib`.
- **Note**: Operation names are from the pool's viewpoint. For example, "send" means the pool is transferring assets to an external party.

### Masks and Flags 🎭

- Flags are used to modify or extend the behavior of an operation. 
- Masks, like `SWAP_DIR = 0x01`, are used to work with flags. For example:
  - To set a flag on an operation: `operationCode |= SWAP_DIR`
  - To check if a flag is set on an operation: `operationCode & SWAP_DIR != 0`

## Supported Operations 🔧

The `Ops` library delineates all the operations permissible by the swap contracts. These operations are enumerated as constants. 

### List of Operations

- **SWAP Operation**: Used for swapping transactions.
  - **Operation Code**: `SWAP = 0x00`
  - **Direction Flag**: 
    - Extracts the direction of the operation.
    - `SWAP_DIR = 0x01`
  - **Deadline Flag**: 
    - Add a deadline to the swap operation.
    - `SWAP_DEADLINE = 0x02`

- **SEND_ALL Operation**: Allows the pool to send all tokens to the user.
  - **Operation Code**: `SEND_ALL = 0x10`

- **RECEIVE_ALL Operation**: Allows the user to send all tokens to the pool.
  - **Operation Code**: `RECEIVE_ALL = 0x20`

- **SEND Operation**: Allows the pool to send tokens to the user.
  - **Operation Code**: `SEND = 0x30`

- **RECEIVE Operation**: Allows the user to send tokens to the pool.
  - **Operation Code**: `RECEIVE = 0x40`

- **PERMIT_WITHDRAW_VIA_SIG Operation**: Enables permit functionality using EIP-2612.
  - **Operation Code**: `PERMIT_WITHDRAW_VIA_SIG = 0x50`

- **ADD_LIQ Operation**: Adds liquidity to the pool.
  - **Operation Code**: `ADD_LIQ = 0x60`

- **RM_LIQ Operation**: Removes liquidity from the pool.
  - **Operation Code**: `RM_LIQ = 0x70`

- **CLAIM_ALL_FEES Operation**: Allows the operator to claim all fees.
  - **Operation Code**: `CLAIM_ALL_FEES = 0x80`

### Masks for `ALL` Operations
- **Minimum Token Amount**:
  - `ALL_MIN_BOUND = 0x01` (with mask `0001`)
  
- **Maximum Token Amount**:
  - `ALL_MAX_BOUND = 0x02` (with mask `0010`)

For an intricate understanding, consider examining the `Ops` library's source code.


## Installation & Usage Instructions 🛠

### Prerequisites

To compile and test the contracts, we utilize [foundry](https://github.com/foundry-rs/foundry). Make sure to familiarize yourself with its environment and setup.

### Building the Smart Contracts

To build all the smart contracts, run:

```bash
forge build
```

### Running Tests

To execute all the unit tests, use:

```bash
forge test
```

### Checking Test Coverage

To view the coverage of unit tests, run:

```bash
forge coverage
```

### Checking Gas Consumption Difference

To assess the differences in gas consumption based on the latest changes, execute:

```bash
forge snapshot --diff
```

### Updating Snapshot Report

To update the snapshot report, run:

```bash
forge snapshot
```

### Static Analysis with Slither

Before running Slither for code analysis, ensure you have it installed. If not, refer to the official [Slither Documentation](https://github.com/crytic/slither).

Once installed, use the following command to analyze the code:

```bash
slither --config-file tools/slither.config.json .
```

## Security Audits 🔒

For transparency and trust, each security audit conducted on our contracts is meticulously documented. We provide details of the auditors, the context or purpose of the audit, the date, and the files covered. Below is a summary of all the audits conducted:

### Audits:

1. **Audit by [nisedo](https://twitter.com/nisedo_) - 20/08/2023**
   - **Context**: General overview of the project.
   - **Files Covered**:
     - `MonoPool.sol`
   - [View Audit Report](audits/nisedo-20-08-2023.md)

2. **Audit by [Mlome](https://twitter.com/0xMlome) - 24/08/2023**
   - **Context**: Brief security audit of the project.
   - **Files Covered**:
     ALL
   - [View Audit Report](audits/Mlome-20-08-2023.md)

## Credits & Acknowledgments 👏

We owe a debt of gratitude to the foundational work done by [Philogy](https://github.com/Philogy/singleton-swapper). Our implementation, while unique, has been greatly inspired by or derives from their stellar work on the singleton-swapper repository.

## Authors 🖋️

- **KONFeature** - [Profile](https://github.com/KONFeature) - Main Author and Developer.
- **Philogy** - [Profile](https://github.com/Philogy/singleton-swapper) - Credits for foundational work.

## License ⚖️

This project is licensed under the AGPL-3.0-only License. Portions of the codebase are derived or inspired by projects under their respective licenses. Always ensure compatibility when integrating or modifying the code.

