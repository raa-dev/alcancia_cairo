# Alcancia - Starknet Savings Contracts

A comprehensive savings platform built on Starknet that enables group savings, individual savings goals, and yield management through integration with ERC4626-compatible lending pools.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Environment Setup](#environment-setup)
- [Dependencies](#dependencies)
- [Project Structure](#project-structure)
- [Smart Contracts](#smart-contracts)
  - [GroupSavings](#groupsavings)
  - [YieldManager](#yieldmanager)
  - [IndividualSavings](#individualsavings)
- [How It Works](#how-it-works)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security Considerations](#security-considerations)

## Overview

Alcancia is a decentralized savings platform on Starknet that provides three main functionalities:

1. **Group Savings**: Multiple users can pool funds together for shared goals (e.g., vacation, group purchases)
2. **Individual Savings**: Users can create personal savings goals with targets and deadlines
3. **Yield Management**: Automated yield distribution from ERC4626-compatible lending pools (Vesu, Nostra, etc.)

All contracts integrate with external ERC20 tokens and can optionally deposit funds into lending pools to generate yield.

## Architecture

![](/docs/alcancia_workflow_2.png)

## Environment Setup

### Prerequisites

- **Rust**: Install Rust (latest stable version)
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```

- **Scarb**: Cairo package manager
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh
  ```

- **Starknet Foundry (snforge)**: Testing framework
  ```bash
    curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | bash
  ```

- **sncast**: Starknet deployment tool
  ```bash
    cargo install --git https://github.com/foundry-rs/starknet-foundry --bin sncast
  ```

### Initial Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd alcancia_cairo
   ```

2. **Install dependencies**
   ```bash
   scarb build
   ```

3. **Create environment file** (for deployment)
   ```bash
   cp .env.example .env
   # Edit .env with your Starknet account details
   ```

## Dependencies

The project uses the following dependencies (defined in `Scarb.toml`):

- **starknet**: `2.11.4` - Core Starknet library
- **openzeppelin**: `2.0.0` - OpenZeppelin Cairo contracts library
- **snforge_std**: `0.46.0` - Starknet Foundry testing utilities (dev dependency)
- **assert_macros**: `2.11.4` - Assertion macros for testing (dev dependency)

## Project Structure

```
alcancia_cairo/
├── Scarb.toml              # Project configuration and dependencies
├── Scarb.lock              # Locked dependency versions
├── snfoundry.toml          # Starknet Foundry configuration
├── src/
│   ├── lib.cairo           # Main contracts (GroupSavings, YieldManager, IndividualSavings)
│   ├── mock_erc20.cairo    # Mock ERC20 token for testing
│   └── mock_lending_pool.cairo  # Mock ERC4626 lending pool for testing
├── tests/
│   ├── test_group_savings.cairo
│   ├── test_yieldmanager.cairo
│   └── test_individual_savings.cairo
├── scripts/
│   └── deploy.sh           # Deployment script
└── docs/
    └── CONTRACT_WORKFLOWS.md  # Detailed contract workflows and diagrams
```

## Smart Contracts

### GroupSavings

Enables multiple users to pool funds together for shared savings goals.

**Key Features:**
- Group registration with custom names and member lists
- Individual member deposits and withdrawals
- Proportional yield distribution based on contributions
- Integration with ERC4626 lending pools for yield generation

**Main Functions:**
- `register_group(group_id, name, members[])` - Create a new savings group
- `save(group_id, member, amount)` - Deposit funds to a group
- `withdraw(group_id, member, amount)` - Withdraw funds from a group
- `distribute_yield(group_id)` - Distribute yield proportionally to members
- `get_member_savings(group_id, member)` - Query member's savings balance
- `get_group_total(group_id)` - Query total group savings

**Access Control:**
- Admin can set token address and lending pool
- Only registered group members can deposit/withdraw for themselves

### YieldManager

Manages yield distribution for authorized contracts with bonus/penalty support.

**Key Features:**
- Authorized caller system (only approved contracts can deposit)
- Proportional yield distribution from lending pools
- Bonus and penalty system for users
- Automatic yield calculation from ERC4626 pools

**Main Functions:**
- `deposit(from, user, amount)` - Deposit funds (authorized callers only)
- `withdraw(user, amount)` - Withdraw funds
- `distribute_yield()` - Distribute yield to all users proportionally
- `set_authorized_caller(contract, is_auth)` - Authorize/revoke contracts
- `set_penalty(user, amount)` - Apply penalty to user
- `set_bonus(user, amount)` - Apply bonus to user

**Access Control:**
- Admin can configure token, lending pool, and authorized callers
- Only authorized contracts can deposit on behalf of users
- Users can withdraw their own funds

### IndividualSavings

Allows users to create and manage personal savings goals.

**Key Features:**
- Create savings goals with target amounts and deadlines
- Track progress toward goals
- Automatic goal completion when target is reached
- Penalty and bonus system
- Integration with lending pools for yield generation

**Main Functions:**
- `create_savings_goal(goal_id, target_amount, deadline, description)` - Create a new goal
- `deposit(goal_id, amount)` - Deposit funds to a goal
- `withdraw(goal_id, amount)` - Withdraw funds from a goal
- `complete_goal(goal_id)` - Manually complete a goal
- `apply_penalty(goal_id, penalty_amount)` - Apply penalty to a goal
- `apply_bonus(goal_id, bonus_amount)` - Apply bonus to a goal
- `get_goal_progress(goal_id)` - Query goal progress

**Access Control:**
- Owner can set token address and lending pool
- Only goal owner can manage their goals

## How It Works

### Token Flow Pattern

All contracts follow a standard token approval and transfer pattern:

1. User approves contract to spend tokens: `ERC20.approve(contract, amount)`
2. Contract transfers tokens: `ERC20.transfer_from(user, contract, amount)`
3. Contract optionally deposits to lending pool: `LendingPool.deposit(amount, contract)`
4. On withdrawal: Contract withdraws from pool (if configured) and transfers to user

### Yield Distribution Pattern

Yield is calculated and distributed proportionally:

1. Contract queries lending pool: `LendingPool.total_assets()`
2. Calculate yield: `current_assets - last_checkpoint`
3. For each user/member: `(yield * user_balance) / total_deposited`
4. Apply bonuses/penalties (YieldManager only)
5. Update user yield balances
6. Update checkpoint for next distribution

### Group Membership Validation

GroupSavings validates membership before operations:

1. Verify group exists
2. Verify caller is the member (can only save/withdraw for themselves)
3. Verify member is part of the group

### Goal Completion Pattern

IndividualSavings automatically completes goals:

1. On deposit, check if `current_amount >= target_amount`
2. If reached, mark goal as completed
3. Emit `GoalCompleted` event

For detailed workflows and sequence diagrams, see [docs/CONTRACT_WORKFLOWS.md](docs/CONTRACT_WORKFLOWS.md).

## Testing

### Running Tests

Run all tests:
```bash
scarb test
# or
snforge test
```

Run specific test file:
```bash
snforge test --path tests/test_group_savings.cairo
```

### Test Structure

Tests use Starknet Foundry's testing framework with:
- **Mock contracts**: `MockERC20` and `MockLendingPool` for isolated testing
- **Cheat codes**: `start_cheat_caller_address` to simulate different callers
- **Assertions**: Standard Cairo assertions for validation

### Example Test Flow

```cairo
#[test]
fn test_register_group_and_save() {
    // 1. Deploy contracts
    let (contract_address, token_address) = setup_token_and_contract();
    
    // 2. Register group
    dispatcher.register_group(1, 100, array![10, 20]);
    
    // 3. Mint tokens and approve
    token.mint(caller, 1000);
    token.approve(contract_address, 1000);
    
    // 4. Deposit
    dispatcher.save(1, 10, 50);
    
    // 5. Verify balances
    assert(dispatcher.get_member_savings(1, 10) == 50, 0);
}
```

## Deployment

### Prerequisites for Deployment

1. **Starknet Account**: Set up an account (Argent, Braavos, etc.)
2. **Environment Variables**: Create `.env` file with:
   ```bash
   ARGENT_PRIVATE_KEY=your_private_key
   ARGENT_PUBLIC_KEY=your_public_key
   ARGENT_ADDRESS=your_account_address
   ```

3. **Network Configuration**: Configure `snfoundry.toml` with your RPC endpoint

### Deployment Steps

#### Option 1: Using the Deployment Script

```bash
# Make script executable
chmod +x scripts/deploy.sh

# Run deployment
./scripts/deploy.sh
```

The script will:
1. Build all contracts
2. Declare contract classes
3. Deploy contracts with constructor parameters
4. Save deployed addresses to `deployed_addresses_mainnet.txt`

#### Option 2: Manual Deployment

1. **Build contracts**
   ```bash
   scarb build
   ```

2. **Declare contract class**
   ```bash
   sncast --profile mainnet declare --contract-name groupsavings
   ```

3. **Deploy contract**
   ```bash
   sncast --profile mainnet deploy \
     --class-hash <CLASS_HASH> \
     --constructor-calldata <ADMIN_ADDRESS>
   ```

### Post-Deployment Configuration

After deployment, configure each contract:

1. **Set Token Address**
   ```bash
   sncast --profile mainnet invoke \
     --contract-address <CONTRACT_ADDRESS> \
     --function set_token_address \
     --calldata <TOKEN_ADDRESS>
   ```

2. **Set Lending Pool** (optional)
   ```bash
   sncast --profile mainnet invoke \
     --contract-address <CONTRACT_ADDRESS> \
     --function set_lending_pool \
     --calldata <LENDING_POOL_ADDRESS>
   ```

3. **For YieldManager: Authorize Callers**
   ```bash
   sncast --profile mainnet invoke \
     --contract-address <YIELD_MANAGER_ADDRESS> \
     --function set_authorized_caller \
     --calldata <AUTHORIZED_CONTRACT> 1
   ```

### Deployment Networks

The project supports multiple networks via `snfoundry.toml`:

- **Sepolia Testnet**: `sncast --profile sepolia`
- **Mainnet**: `sncast --profile mainnet`

## Security Considerations

1. **Access Control**: All contracts use admin/owner checks for configuration
2. **Input Validation**: All functions validate inputs (non-zero amounts, valid addresses, etc.)
3. **Balance Checks**: Withdrawals always check sufficient balance before transfer
4. **Authorization**: YieldManager requires explicit authorization for deposits
5. **Group Validation**: GroupSavings validates membership before operations
6. **Goal Ownership**: IndividualSavings verifies goal ownership for all operations
7. **Reentrancy Protection**: Cairo's execution model provides natural reentrancy protection

## Additional Resources

- [Contract Workflows Documentation](docs/CONTRACT_WORKFLOWS.md) - Detailed workflows and sequence diagrams
- [Starknet Documentation](https://docs.starknet.io/)
- [Cairo Documentation](https://cairo-book.github.io/)
- [Scarb Documentation](https://docs.swmansion.com/scarb/)
- [Starknet Foundry Documentation](https://foundry-rs.github.io/starknet-foundry/)

## License

MIT License - See LICENSE file for details

