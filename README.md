# ERC-4337 Account Abstraction Implementation

A complete implementation of ERC-4337 Account Abstraction standard using Foundry. This project demonstrates how to create smart contract wallets that enable gasless transactions, transaction batching, and improved user experience on Ethereum.

## Table of Contents

-   [What is Account Abstraction?](#what-is-account-abstraction)
-   [ERC-4337 Flow](#erc-4337-flow)
-   [Project Architecture](#project-architecture)
-   [Core Components](#core-components)
-   [Smart Contracts](#smart-contracts)
-   [Scripts](#scripts)
-   [Getting Started](#getting-started)
-   [Usage](#usage)
-   [Testing](#testing)

---

## What is Account Abstraction?

**Account Abstraction (AA)** revolutionizes how users interact with Ethereum by allowing smart contracts to be the primary accounts instead of Externally Owned Accounts (EOAs).

### Traditional Accounts vs Smart Contract Accounts

| Feature           | EOA (Traditional)               | Smart Contract Account (AA)                      |
| ----------------- | ------------------------------- | ------------------------------------------------ |
| **Gas Payment**   | Must hold ETH                   | Can pay with any ERC20 token                     |
| **Signature**     | ECDSA only                      | Any signature scheme (multisig, social recovery) |
| **Batching**      | One transaction at a time       | Batch multiple operations                        |
| **Recovery**      | Lose private key = lose account | Programmable recovery mechanisms                 |
| **Upgradability** | Fixed logic                     | Upgradable logic                                 |

### Benefits of Account Abstraction

1. **Gasless Transactions**: Paymasters can sponsor gas fees
2. **Social Recovery**: Recover your account without seed phrases
3. **Session Keys**: Temporary keys for gaming/DeFi with limited permissions
4. **Transaction Batching**: Approve + transfer in one transaction
5. **Custom Validation Logic**: Implement 2FA, biometrics, or multisig

---

## ERC-4337 Flow

The ERC-4337 standard defines a flow where user operations are validated and executed through a decentralized infrastructure:

### Step-by-Step Flow:

```
┌─────────────────────────────────────────────────────────────────┐
│  1. Smart wallet constructs UserOperation                       │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  2. Bundler picks valid ops from alt-mempool                    │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  3. Bundler submits all ops via EntryPoint.handleOps()          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  4. EntryPoint calls wallet.validateUserOp() (verifies)         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  5. (Optional) paymaster.validatePaymasterUserOp() called       │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  6. EntryPoint executes user's action via wallet.execute()      │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  7. Gas fee settled; bundler refunded; operation complete       │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components in the Flow:

-   **UserOperation**: A data structure containing the transaction details and signature
-   **Bundler**: Off-chain service that collects UserOperations and submits them
-   **EntryPoint**: Singleton contract that validates and executes operations
-   **Smart Account**: Your contract wallet implementing the `IAccount` interface
-   **Paymaster** (Optional): Contract that can sponsor gas fees

---

## Project Architecture

```
account-abstraction/
├── src/
│   └── MinimalAccount.sol          # Smart contract wallet implementation
├── script/
│   ├── DeployAccount.s.sol         # Deployment script
│   ├── HelperConfig.s.sol          # Network configurations
│   └── SendPackedUserOp.s.sol      # Script to send user operations
├── test/
│   └── MinimalAccountTest.t.sol    # Comprehensive test suite
└── lib/
    ├── account-abstraction/        # Official ERC-4337 contracts
    ├── openzeppelin-contracts/     # OpenZeppelin utilities
    └── forge-std/                  # Foundry standard library
```

---

## Core Components

### 1. **EntryPoint Contract**

The **EntryPoint** is the singleton contract defined by ERC-4337 that:

-   Acts as the central hub for all account abstraction operations
-   Validates user operations through the account's `validateUserOp` function
-   Executes validated operations
-   Manages gas accounting and refunds
-   Coordinates with paymasters for gas sponsorship

**Address**:

-   Mainnet: `0x0000000071727De22E5E9d8BAf0edAc6f37da032` (v0.7)
-   Sepolia: `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`

### 2. **UserOperation Structure**

A `PackedUserOperation` contains:

-   `sender`: The smart account address
-   `nonce`: Anti-replay protection
-   `initCode`: Code to deploy the account (if not yet deployed)
-   `callData`: The actual transaction data to execute
-   `accountGasLimits`: Gas limits for validation and execution
-   `preVerificationGas`: Gas for bundler overhead
-   `gasFees`: Max fee and priority fee per gas
-   `paymasterAndData`: Paymaster address and data (if using one)
-   `signature`: Signature over the operation

### 3. **Bundler**

An off-chain service that:

-   Monitors the alternative mempool for UserOperations
-   Validates operations before submitting
-   Batches multiple UserOperations into a single transaction
-   Calls `EntryPoint.handleOps()` to execute them
-   Gets refunded for gas costs

---

## Smart Contracts

### MinimalAccount.sol

The core smart contract wallet implementing the `IAccount` interface.

#### Key Features:

```solidity
contract MinimalAccount is IAccount, Ownable {
    IEntryPoint private immutable I_ENTRY_POINT;

    // Core functions:

    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);

    function execute(
        address dest,
        uint256 value,
        bytes calldata functionData
    ) external;
}
```

#### Function Breakdown:

1. **`constructor(address entryPoint)`**

    - Initializes the account with a reference to the EntryPoint
    - Sets the deployer as the owner

2. **`validateUserOp()`**

    - Called by EntryPoint during the verification step
    - Validates the signature using ECDSA
    - Pays prefund to the EntryPoint for gas
    - Returns `0` for success, `1` for failure

3. **`execute()`**

    - Executes arbitrary calls to other contracts
    - Protected by `requireFromEntryPointOrOwner` modifier
    - Enables the account to interact with DeFi, NFTs, etc.

4. **`_validateSignature()`**

    - Recovers the signer from the UserOperation signature
    - Verifies the signer is the account owner
    - Uses EIP-191 message signing standard

5. **`_payPrefund()`**
    - Transfers required ETH to EntryPoint for gas costs
    - Ensures the account has sufficient funds

#### Security Features:

-   ✅ Only EntryPoint can call `validateUserOp`
-   ✅ Only EntryPoint or owner can call `execute`
-   ✅ Signature validation prevents unauthorized operations
-   ✅ Nonce management prevents replay attacks

---

## Scripts

### 1. DeployAccount.s.sol

Deploys the `MinimalAccount` contract to any network.

```solidity
function deployMinimalAccount() public returns (HelperConfig, MinimalAccount) {
    HelperConfig helperConfig = new HelperConfig();
    HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

    vm.startBroadcast(config.account);
    MinimalAccount minimalAccount = new MinimalAccount(config.entryPoint);
    minimalAccount.transferOwnership(config.account);
    vm.stopBroadcast();

    return (helperConfig, minimalAccount);
}
```

### 2. HelperConfig.s.sol

Manages network-specific configurations:

```solidity
struct NetworkConfig {
    address entryPoint;    // ERC-4337 EntryPoint address
    address usdc;          // USDC token for testing
    address account;       // Deployer/owner account
}
```

**Supported Networks**:

-   ✅ Ethereum Mainnet
-   ✅ Ethereum Sepolia
-   ✅ Base Mainnet
-   ✅ Local Anvil (with mock deployment)

### 3. SendPackedUserOp.s.sol

Demonstrates how to create and send a UserOperation:

#### What it does:

1. Creates a UserOperation to approve USDC spending
2. Signs the operation with the account owner's private key
3. Submits it to the EntryPoint via `handleOps()`

#### Key Function:

```solidity
function generateSignedUserOperation(
    bytes memory callData,
    HelperConfig.NetworkConfig memory config,
    address minimalAccount
) public view returns (PackedUserOperation memory) {
    // 1. Generate unsigned UserOperation
    // 2. Get UserOp hash from EntryPoint
    // 3. Convert to EIP-191 format
    // 4. Sign with private key
    // 5. Attach signature to UserOperation
}
```

---

## Getting Started

### Prerequisites

-   [Foundry](https://book.getfoundry.sh/getting-started/installation)
-   Git

### Installation

```shell
git clone https://github.com/your-username/account-abstraction.git
cd account-abstraction
forge install
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
forge test -vvv
```

**Run specific test:**

```shell
forge test --match-test testOwnerCanExecuteCommands -vvv
```

---

## Deployment

### Deploy to Local Anvil

1. **Start Anvil:**

```shell
anvil
```

2. **Deploy MinimalAccount:**

```shell
forge script script/DeployAccount.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Deploy to Sepolia

1. **Set up environment variables:**

```shell
export PRIVATE_KEY=your_private_key_here
export SEPOLIA_RPC_URL=your_sepolia_rpc_url
```

2. **Deploy:**

```shell
forge script script/DeployAccount.s.sol:DeployMinimal --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

### Deploy to Mainnet

⚠️ **Warning**: Ensure thorough testing before mainnet deployment!

```shell
forge script script/DeployAccount.s.sol:DeployMinimal \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

---

## Testing

The project includes comprehensive tests demonstrating all functionality:

### Test Suite (`MinimalAccountTest.t.sol`)

#### 1. **testOwnerCanExecuteCommands**

-   Verifies the owner can directly execute commands
-   Mints USDC tokens to the MinimalAccount
-   Asserts balance changes correctly

#### 2. **testRecoverSignedOp**

-   Tests signature recovery from a UserOperation
-   Verifies the recovered signer matches the account owner
-   Ensures cryptographic integrity

#### 3. **testValidateUserOps**

-   Tests the `validateUserOp` function
-   Simulates EntryPoint validation
-   Checks return value for success (0) or failure (1)

#### 4. **testEntryPointCanExecuteCommands**

-   End-to-end test of the full AA flow
-   Creates signed UserOperation
-   Submits through EntryPoint's `handleOps`
-   Verifies successful execution

### Run Tests with Verbose Output

```shell
forge test -vvvv
```

This shows:

-   ✅ Transaction traces
-   ✅ Gas usage
-   ✅ Event logs
-   ✅ Call stacks

---

## Usage Examples

### Example 1: Approve ERC20 Token

```solidity
// In SendPackedUserOp.s.sol
bytes memory functionData = abi.encodeWithSelector(
    IERC20.approve.selector,
    spenderAddress,
    1e18
);

bytes memory executeCalldata = abi.encodeWithSelector(
    MinimalAccount.execute.selector,
    usdcAddress,
    0,
    functionData
);

// Create and sign UserOperation
PackedUserOperation memory userOp = generateSignedUserOperation(
    executeCalldata,
    config,
    minimalAccountAddress
);

// Submit to EntryPoint
IEntryPoint(entryPoint).handleOps(ops, payable(bundler));
```

### Example 2: Batch Multiple Operations

```solidity
// Approve + Transfer in one UserOperation
bytes memory approveTx = abi.encodeWithSelector(
    IERC20.approve.selector,
    spender,
    amount
);

bytes memory transferTx = abi.encodeWithSelector(
    IERC20.transfer.selector,
    recipient,
    amount
);

// Execute both in sequence through your account
```

### Example 3: Gasless Transaction with Paymaster

```solidity
PackedUserOperation memory userOp = PackedUserOperation({
    sender: accountAddress,
    nonce: nonce,
    initCode: hex"",
    callData: executeCalldata,
    accountGasLimits: ...,
    preVerificationGas: ...,
    gasFees: ...,
    paymasterAndData: abi.encodePacked(paymasterAddress, paymasterData),
    signature: signature
});
```

---

## Network Information

### EntryPoint Deployments

| Network          | EntryPoint Address                           | Version |
| ---------------- | -------------------------------------------- | ------- |
| Ethereum Mainnet | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | v0.7    |
| Sepolia Testnet  | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` | v0.6    |
| Base Mainnet     | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | v0.7    |
| Arbitrum One     | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | v0.7    |
| Optimism         | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | v0.7    |
| Polygon          | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | v0.7    |

---

## Additional Resources

### Official Documentation

-   [ERC-4337 Specification](https://eips.ethereum.org/EIPS/eip-4337)
-   [Account Abstraction Official Repo](https://github.com/eth-infinitism/account-abstraction)
-   [Foundry Book](https://book.getfoundry.sh/)

### Learning Materials

-   [Vitalik's Account Abstraction Post](https://vitalik.eth.limo/general/2023/06/09/three_transitions.html)
-   [EIP-4337 Deep Dive](https://www.erc4337.io/)

### Tools & Services

-   **Bundlers**: [Alto](https://github.com/pimlicolabs/alto), [Stackup](https://www.stackup.sh/)
-   **Paymasters**: [Pimlico](https://www.pimlico.io/), [Biconomy](https://www.biconomy.io/)

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

-   [Eth-Infinitism](https://github.com/eth-infinitism/account-abstraction) for the ERC-4337 reference implementation
-   [OpenZeppelin](https://www.openzeppelin.com/) for secure contract libraries
-   [Foundry](https://github.com/foundry-rs/foundry) for the incredible development toolkit
-   [Cyfrin](https://www.cyfrin.io/) for educational resources
