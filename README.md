# swap-pool 😎

A modular Solidity-based solution handling asset swaps within the [Frak](https://frak.id/) ecosystem. Streamlined, secure, and designed with developers in mind.

## Table of Contents 📚

- [Prerequisites](#prerequisites) 🔧
- [Installation](#installation) 🛠️
- [How It Works](#how-it-works) 🧠
- [Contract Structure](#contract-structure) 📜
- [Credits & Acknowledgments](#credits--acknowledgments) 👏
- [Features](#features) 🌟
- [Authors](#authors) 🖋️
- [License](#license) ⚖️

## Prerequisites 🔧

To compile and test the contracts, we utilize [foundry](https://github.com/foundry-rs/foundry). Make sure to familiarize yourself with its environment and setup.

## Installation 🛠️

> **Note**: Detailed installation steps will be provided soon.

## How It Works 🧠

### Internal Flash Accounting 💡

- The pool uses an "in-memory" method to keep track of all operations, whether they are for providing liquidity or executing multi-hop swaps.
- Instead of making changes immediately, all balance updates are first recorded internally. This helps in only settling the net changes at the end of an operation block.
- To track these changes, a hash-map is utilized, residing solely in memory. The caller specifies its size when beginning a batch of operations:
  - A smaller hash-map is more gas-efficient due to lesser upfront memory allocation. However, it has a higher risk of key collisions, which can make some operations more costly. 
  - The optimal hash-map size can be determined through off-chain transaction simulations.

### Program 📜

- Interactions with the pools are facilitated via the `execute(bytes program)` function.
- The "program" is essentially a serialized set of operations and follows a specific structure:
  - The first 2 bytes denote the accounting hash map size in terms of tokens. For instance, `0x0040` stands for a map that accommodates up to 64 key-value pairs.
  - Every subsequent operation within this program comprises:
    - An 8-bit operation, spanning 1 byte.
    - Data pertaining to the opcode, spanning 'n' bytes.
- This encoding method ensures minimal calldata size, given that each operation might need different data amounts.

### Operations 🔧

- An 8-bit operation specifier contains two parts:
  - The first 4 bits (half) represent the operation ID.
  - The latter 4 bits represent flags.
- Thus, there's the potential for up to 16 primary operations. Each can interpret 4 additional flags.
- Parameters are always packed tightly.
- Encoding of individual operations can be found in the `EncoderLib`.
- **Note**: Operation names are from the pool's viewpoint. For example, "send" means the pool is transferring assets to an external party.

### Supported Operations (Ops) 🛠️

The system has a set of predefined operations that can be executed within the pool. These operations are represented as constants in the `Ops` library.

- **SWAP Operation**: Used for swap transactions.
  - **Operation Type**: `SWAP = 0x00`
  - **Direction Flag**: 
    - Used to extract the operation's direction.
    - `SWAP_DIR = 0x01`

- **SEND_ALL Operation**: Enables the pool to send all tokens to a user.
  - **Operation Type**: `SEND_ALL = 0x10`
  - **Bounds**:
    - Minimum: `ALL_MIN_BOUND = 0x01`
    - Maximum: `ALL_MAX_BOUND = 0x02`

- **RECEIVE_ALL Operation**: Allows a user to send all their tokens to the pool.
  - **Operation Type**: `RECEIVE_ALL = 0x20`
  - **Bounds**:
    - Minimum: `ALL_MIN_BOUND = 0x01`
    - Maximum: `ALL_MAX_BOUND = 0x02`

- **SEND Operation**: Enables the pool to send tokens to a user.
  - **Operation Type**: `SEND = 0x30`

- **RECEIVE Operation**: Allows a user to send tokens to the pool.
  - **Operation Type**: `RECEIVE = 0x40`

- **PERMIT_WITHDRAW_VIA_SIG Operation**: Enables operations using EIP-2612's permit functionality.
  - **Operation Type**: `PERMIT_WITHDRAW_VIA_SIG = 0x50`

- **ADD_LIQ Operation**: Used to add liquidity to the pool.
  - **Operation Type**: `ADD_LIQ = 0x60`

- **RM_LIQ Operation**: Used to remove liquidity from the pool.
  - **Operation Type**: `RM_LIQ = 0x70`

- **CLAIM_ALL_FEES Operation**: Allows the operator to claim fees.
  - **Operation Type**: `CLAIM_ALL_FEES = 0x80`

Each operation is uniquely identified by a combination of its type and possible flags. The `MASK_OP` is used to extract the type of operation, with its value being `MASK_OP = 0xf0`.

## Contract Structure 📜

```ml
.
├── Ops.sol               - Contains the list of all available operations (Ops).
├── encoder
│   ├── DecoderLib.sol    - Helps decode data for each operation.
│   └── EncoderLib.sol    - Assists off-chain users. Not for on-chain use.
└── lib
    ├── AccounterLib.sol  - Library with in-memory accounting logic.
    ├── MemMappingLib.sol - Logic to build in-memory key-value mappings.
    └── SwapLib.sol       - Contains computations related to swap operations.

```

Always remember: Use `EncoderLib` exclusively in off-chain scenarios for optimal gas efficiency.

## Credits & Acknowledgments 👏

We owe a debt of gratitude to the foundational work done by [Philogy](https://github.com/Philogy/singleton-swapper). Our implementation, while unique, has been greatly inspired by or derives from their stellar work on the singleton-swapper repository.

## Features 🌟

- **Pool Per Contract Mechanism**: Enhanced flexibility by allowing a dedicated pool for each contract.
- **In-Memory Accounting**: Optimized performance by handling account balances and transactions in memory.
- **EIP-2612 Permit Signature Support**: Integrated support for EIP-2612 permit signatures, enabling better user experience and security.

## Authors 🖋️

- **KONFeature** - [Profile](https://github.com/KONFeature) - Main Author and Developer.
- **Philogy** - [Profile](https://github.com/Philogy/singleton-swapper) - Credits for foundational work.

## License ⚖️

This project is licensed under the AGPL-3.0-only License. Portions of the codebase are derived or inspired by projects under their respective licenses. Always ensure compatibility when integrating or modifying the code.

