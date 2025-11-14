# Alcancia Contract Workflows and Interactions

This document provides visual diagrams of how each contract works and how they interact with each other.

## System Architecture Overview

```mermaid
graph TB
    subgraph "External Contracts"
        ERC20[ERC20 Token<br/>USDC/USDT/etc]
        LendingPool[Lending Pool<br/>ERC4626 Compatible<br/>Vesu/Nostra/etc]
    end
    
    subgraph "Alcancia Contracts"
        GroupSavings[GroupSavings<br/>Group-based savings]
        YieldManager[YieldManager<br/>Yield distribution]
        IndividualSavings[IndividualSavings<br/>Personal savings goals]
    end
    
    subgraph "Users"
        User1[User 1]
        User2[User 2]
        UserN[User N]
        Admin[Admin]
    end
    
    User1 -->|deposit/withdraw| GroupSavings
    User2 -->|deposit/withdraw| GroupSavings
    UserN -->|create goals| IndividualSavings
    Admin -->|configure| GroupSavings
    Admin -->|configure| YieldManager
    Admin -->|configure| IndividualSavings
    
    GroupSavings -->|transfer_from| ERC20
    GroupSavings -->|deposit/withdraw| LendingPool
    LendingPool -->|yield| GroupSavings
    IndividualSavings -->|transfer_from| ERC20
    IndividualSavings -->|deposit/withdraw| LendingPool
    YieldManager -->|transfer_from| ERC20
    YieldManager -->|deposit/withdraw| LendingPool
    LendingPool -->|yield| YieldManager
    
    style GroupSavings fill:#e1f5ff
    style YieldManager fill:#fff4e1
    style IndividualSavings fill:#e8f5e9
    style ERC20 fill:#f3e5f5
    style LendingPool fill:#fce4ec
```

## GroupSavings Contract Workflow

```mermaid
sequenceDiagram
    participant Admin
    participant User
    participant GroupSavings
    participant ERC20
    
    Note over Admin,ERC20: Setup Phase
    Admin->>GroupSavings: set_token_address(token_address)
    GroupSavings-->>Admin: TokenAddressSet event
    
    Note over Admin,ERC20: Group Registration
    User->>GroupSavings: register_group(group_id, name, members[])
    GroupSavings->>GroupSavings: Validate inputs<br/>Check group doesn't exist<br/>Store group data
    GroupSavings-->>User: GroupRegistered event
    
    Note over Admin,LendingPool: Setup Phase (continued)
    Admin->>GroupSavings: set_lending_pool(lending_pool_address)
    GroupSavings-->>Admin: LendingPoolSet event
    
    Note over Admin,LendingPool: Deposit Workflow
    User->>ERC20: approve(GroupSavings, amount)
    ERC20-->>User: Approval confirmed
    User->>GroupSavings: save(group_id, member, amount)
    GroupSavings->>GroupSavings: Validate group exists<br/>Verify caller is member<br/>Check member in group
    GroupSavings->>ERC20: transfer_from(user, contract, amount)
    ERC20-->>GroupSavings: Tokens transferred
    alt Lending Pool Configured
        GroupSavings->>ERC20: approve(lending_pool, amount)
        GroupSavings->>LendingPool: deposit(amount, contract)
        LendingPool-->>GroupSavings: Shares received
        GroupSavings->>GroupSavings: Update group_total_deposited
        GroupSavings-->>User: TokensDepositedToPool event
    end
    GroupSavings->>GroupSavings: Update member_savings<br/>Update group_totals
    GroupSavings-->>User: SavingsDeposited event
    
    Note over Admin,LendingPool: Yield Distribution Workflow
    Admin->>GroupSavings: distribute_yield(group_id)
    GroupSavings->>LendingPool: total_assets()
    LendingPool-->>GroupSavings: Current total assets
    GroupSavings->>GroupSavings: Calculate yield:<br/>current_assets - last_checkpoint
    loop For each member
        GroupSavings->>GroupSavings: Calculate member share:<br/>(yield * member_balance) / total_deposited
        GroupSavings->>GroupSavings: Update member_yields
        GroupSavings-->>User: YieldDistributed event
    end
    GroupSavings->>GroupSavings: Update last_yield_checkpoint
    
    Note over Admin,LendingPool: Withdraw Workflow
    User->>GroupSavings: withdraw(group_id, member, amount)
    GroupSavings->>GroupSavings: Validate group exists<br/>Verify caller is member<br/>Check sufficient balance
    alt Lending Pool Configured
        GroupSavings->>LendingPool: withdraw(amount, contract, contract)
        LendingPool-->>GroupSavings: Assets received
        GroupSavings->>GroupSavings: Update group_total_deposited
        GroupSavings-->>User: TokensWithdrawnFromPool event
    end
    GroupSavings->>ERC20: transfer(user, amount)
    ERC20-->>User: Tokens transferred
    GroupSavings->>GroupSavings: Update member_savings<br/>Update group_totals
    GroupSavings-->>User: Withdrawal event
```

## YieldManager Contract Workflow

```mermaid
sequenceDiagram
    participant Admin
    participant AuthorizedCaller
    participant YieldManager
    participant ERC20
    participant LendingPool
    participant User
    
    Note over Admin,User: Setup Phase
    Admin->>YieldManager: set_token_address(token_address)
    Admin->>YieldManager: set_lending_pool(lending_pool_address)
    Admin->>YieldManager: set_authorized_caller(contract, true)
    YieldManager-->>Admin: Configuration events
    
    Note over Admin,User: Deposit Workflow
    AuthorizedCaller->>ERC20: approve(YieldManager, amount)
    ERC20-->>AuthorizedCaller: Approval confirmed
    AuthorizedCaller->>YieldManager: deposit(from, user, amount)
    YieldManager->>YieldManager: Validate authorized caller
    YieldManager->>ERC20: transfer_from(authorized_caller, contract, amount)
    ERC20-->>YieldManager: Tokens transferred
    YieldManager->>YieldManager: Update user balance<br/>Register user if new
    alt Lending Pool Configured
        YieldManager->>ERC20: approve(lending_pool, amount)
        YieldManager->>LendingPool: deposit(amount, yield_manager)
        LendingPool-->>YieldManager: Shares received
        YieldManager->>YieldManager: Update total_deposited
    end
    YieldManager-->>AuthorizedCaller: Deposit event
    
    Note over Admin,User: Yield Distribution Workflow
    Admin->>YieldManager: distribute_yield()
    YieldManager->>LendingPool: total_assets()
    LendingPool-->>YieldManager: Current total assets
    YieldManager->>YieldManager: Calculate yield:<br/>current_assets - last_checkpoint
    loop For each user
        YieldManager->>YieldManager: Calculate user share:<br/>(yield * user_balance) / total_deposited
        YieldManager->>YieldManager: Apply bonuses and penalties
        YieldManager->>YieldManager: Update user yield
        YieldManager-->>User: YieldDistributed event
    end
    YieldManager->>YieldManager: Update last_yield_checkpoint<br/>Reset penalties/bonuses
    
    Note over Admin,User: Withdraw Workflow
    User->>YieldManager: withdraw(user, amount)
    YieldManager->>YieldManager: Validate sufficient balance
    alt Lending Pool Configured
        YieldManager->>LendingPool: withdraw(amount, yield_manager, yield_manager)
        LendingPool-->>YieldManager: Assets received
        YieldManager->>YieldManager: Update total_deposited
    end
    YieldManager->>ERC20: transfer(user, amount)
    ERC20-->>User: Tokens transferred
    YieldManager->>YieldManager: Update user balance
    YieldManager-->>User: Withdrawal event
```

## IndividualSavings Contract Workflow

```mermaid
sequenceDiagram
    participant Owner
    participant IndividualSavings
    participant ERC20
    participant LendingPool
    
    Note over Owner,LendingPool: Setup Phase
    Owner->>IndividualSavings: set_token_address(token_address)
    IndividualSavings-->>Owner: TokenAddressSet event
    Owner->>IndividualSavings: set_lending_pool(lending_pool_address)
    IndividualSavings-->>Owner: LendingPoolSet event
    
    Note over Owner,ERC20: Create Goal Workflow
    Owner->>IndividualSavings: create_savings_goal(goal_id, target_amount, deadline, description)
    IndividualSavings->>IndividualSavings: Validate goal doesn't exist<br/>Validate target > 0<br/>Validate deadline in future
    IndividualSavings->>IndividualSavings: Store goal data<br/>Initialize penalties/bonuses to 0
    IndividualSavings-->>Owner: GoalCreated event
    
    Note over Owner,LendingPool: Deposit Workflow
    Owner->>ERC20: approve(IndividualSavings, amount)
    ERC20-->>Owner: Approval confirmed
    Owner->>IndividualSavings: deposit(goal_id, amount)
    IndividualSavings->>IndividualSavings: Validate goal exists<br/>Verify caller is owner<br/>Check goal not completed
    IndividualSavings->>ERC20: transfer_from(owner, contract, amount)
    ERC20-->>IndividualSavings: Tokens transferred
    alt Lending Pool Configured
        IndividualSavings->>ERC20: approve(lending_pool, amount)
        IndividualSavings->>LendingPool: deposit(amount, contract)
        LendingPool-->>IndividualSavings: Shares received
        IndividualSavings->>IndividualSavings: Update goal_total_deposited
        IndividualSavings-->>Owner: TokensDepositedToPool event
    end
    IndividualSavings->>IndividualSavings: Update goal_current_amounts
    IndividualSavings-->>Owner: Deposit event
    IndividualSavings-->>Owner: ProgressUpdated event
    alt Goal Target Reached
        IndividualSavings->>IndividualSavings: Mark goal as completed
        IndividualSavings-->>Owner: GoalCompleted event
    end
    
    Note over Owner,LendingPool: Withdraw Workflow
    Owner->>IndividualSavings: withdraw(goal_id, amount)
    IndividualSavings->>IndividualSavings: Validate goal exists<br/>Verify caller is owner<br/>Check goal not completed<br/>Check sufficient funds
    alt Lending Pool Configured
        IndividualSavings->>LendingPool: withdraw(amount, contract, contract)
        LendingPool-->>IndividualSavings: Assets received
        IndividualSavings->>IndividualSavings: Update goal_total_deposited
        IndividualSavings-->>Owner: TokensWithdrawnFromPool event
    end
    IndividualSavings->>ERC20: transfer(owner, amount)
    ERC20-->>Owner: Tokens transferred
    IndividualSavings->>IndividualSavings: Update goal_current_amounts
    IndividualSavings-->>Owner: Withdrawal event
    IndividualSavings-->>Owner: ProgressUpdated event
    
    Note over Owner,ERC20: Complete Goal Workflow
    Owner->>IndividualSavings: complete_goal(goal_id)
    IndividualSavings->>IndividualSavings: Validate goal exists<br/>Verify caller is owner<br/>Check goal not already completed<br/>Check target reached
    IndividualSavings->>IndividualSavings: Mark goal as completed
    IndividualSavings-->>Owner: GoalCompleted event
    
    Note over Owner,ERC20: Penalty/Bonus Workflow
    Owner->>IndividualSavings: apply_penalty(goal_id, penalty_amount)
    IndividualSavings->>IndividualSavings: Validate goal exists<br/>Verify caller is owner
    IndividualSavings->>IndividualSavings: Update goal_penalties
    IndividualSavings-->>Owner: PenaltyApplied event
    
    Owner->>IndividualSavings: apply_bonus(goal_id, bonus_amount)
    IndividualSavings->>IndividualSavings: Validate goal exists<br/>Verify caller is owner
    IndividualSavings->>IndividualSavings: Update goal_bonuses
    IndividualSavings-->>Owner: BonusApplied event
```

## Contract Interaction Patterns

```mermaid
graph LR
    subgraph "Token Flow"
        direction TB
        User[User Wallet] -->|1. approve| ERC20[ERC20 Token]
        ERC20 -->|2. transfer_from| Contract[Savings Contract]
        Contract -->|3. transfer| User
    end
    
    subgraph "Yield Flow"
        direction TB
        YM[YieldManager] -->|1. approve| ERC20
        YM -->|2. deposit| LP[Lending Pool]
        LP -->|3. yield generation| LP
        LP -->|4. total_assets| YM
        YM -->|5. distribute_yield| Users[Users]
    end
    
    subgraph "Authorization Flow"
        direction TB
        Admin[Admin] -->|set_authorized_caller| YM
        AuthContract[Authorized Contract] -->|deposit| YM
        YM -->|validates| AuthCheck{Is Authorized?}
        AuthCheck -->|Yes| Process[Process Deposit]
        AuthCheck -->|No| Reject[Reject Transaction]
    end
    
    style ERC20 fill:#f3e5f5
    style LP fill:#fce4ec
    style YM fill:#fff4e1
    style Contract fill:#e1f5ff
```

## State Management Diagrams

### GroupSavings State Structure

```mermaid
graph TB
    subgraph "GroupSavings Storage"
        GS[GroupSavings Contract]
        GS --> GN[group_names: Map<group_id, name>]
        GS --> GM[group_members: Map<group_id, index, member>]
        GS --> GSZ[group_sizes: Map<group_id, size>]
        GS --> MS[member_savings: Map<group_id, member, amount>]
        GS --> GT[group_totals: Map<group_id, total>]
        GS --> GC[group_creators: Map<group_id, creator>]
        GS --> GR[group_registered: Map<group_id, bool>]
        GS --> TA[token_address: Map<address>]
        GS --> AD[admin: Map<address>]
    end
```

### YieldManager State Structure

```mermaid
graph TB
    subgraph "YieldManager Storage"
        YM[YieldManager Contract]
        YM --> BAL[balances: Map<user, balance>]
        YM --> YLD[yields: Map<user, yield>]
        YM --> AC[authorized_callers: Map<contract, bool>]
        YM --> STR[strategy: Map<user, address>]
        YM --> LP[lending_pool: Map<user, address>]
        YM --> AD[admin: Map<user, address>]
        YM --> PEN[penalties: Map<user, amount>]
        YM --> BON[bonuses: Map<user, amount>]
        YM --> USR[users: Map<index, user>]
        YM --> UC[user_count: Map<user, count>]
        YM --> TA[token_address: Map<user, address>]
        YM --> TD[total_deposited: Map<user, amount>]
        YM --> LC[last_yield_checkpoint: Map<user, assets>]
    end
```

### IndividualSavings State Structure

```mermaid
graph TB
    subgraph "IndividualSavings Storage"
        IS[IndividualSavings Contract]
        IS --> GO[goal_owners: Map<goal_id, owner>]
        IS --> GT[goal_targets: Map<goal_id, target>]
        IS --> GD[goal_deadlines: Map<goal_id, deadline>]
        IS --> GDESC[goal_descriptions: Map<goal_id, description>]
        IS --> GCA[goal_current_amounts: Map<goal_id, amount>]
        IS --> GCT[goal_created_at: Map<goal_id, timestamp>]
        IS --> GC[goal_completed: Map<goal_id, bool>]
        IS --> GP[goal_penalties: Map<goal_id, penalty>]
        IS --> GB[goal_bonuses: Map<goal_id, bonus>]
        IS --> UG[user_goals: Map<<user, index>, goal_id>]
        IS --> UGC[user_goal_counts: Map<user, count>]
        IS --> OW[owner: Map<(), address>]
        IS --> TA[token_address: Map<(), address>]
    end
```

## Complete System Flow Example

```mermaid
sequenceDiagram
    participant User1
    participant User2
    participant Admin
    participant GroupSavings
    participant ERC20
    participant LendingPool
    
    Note over User1,LendingPool: Complete Example: Group Savings with Direct Lending Pool Integration
    
    Admin->>ERC20: Deploy/Mint tokens
    Admin->>GroupSavings: Deploy & set_token_address
    Admin->>GroupSavings: set_lending_pool(lending_pool_address)
    Admin->>LendingPool: Deploy
    
    User1->>GroupSavings: register_group(group_id, "Vacation", [user1, user2])
    GroupSavings-->>User1: GroupRegistered
    
    User1->>ERC20: approve(GroupSavings, 1000)
    User1->>GroupSavings: save(group_id, user1, 1000)
    GroupSavings->>ERC20: transfer_from(user1, GroupSavings, 1000)
    GroupSavings->>ERC20: approve(LendingPool, 1000)
    GroupSavings->>LendingPool: deposit(1000, GroupSavings)
    LendingPool-->>GroupSavings: Shares
    GroupSavings->>GroupSavings: Update group_total_deposited: 1000
    GroupSavings-->>User1: SavingsDeposited
    
    User2->>ERC20: approve(GroupSavings, 500)
    User2->>GroupSavings: save(group_id, user2, 500)
    GroupSavings->>ERC20: transfer_from(user2, GroupSavings, 500)
    GroupSavings->>ERC20: approve(LendingPool, 500)
    GroupSavings->>LendingPool: deposit(500, GroupSavings)
    LendingPool-->>GroupSavings: Shares
    GroupSavings->>GroupSavings: Update group_total_deposited: 1500
    GroupSavings-->>User2: SavingsDeposited
    
    Note over User1,LendingPool: Yield Distribution (Proportional to Contributions)
    Admin->>GroupSavings: distribute_yield(group_id)
    GroupSavings->>LendingPool: total_assets()
    LendingPool-->>GroupSavings: 1575 (5% yield)
    GroupSavings->>GroupSavings: Calculate yield: 75<br/>User1: 66.67% (50 yield)<br/>User2: 33.33% (25 yield)
    GroupSavings->>GroupSavings: Update member_yields
    GroupSavings-->>User1: YieldDistributed (50)
    GroupSavings-->>User2: YieldDistributed (25)
    
    Note over User1,LendingPool: Withdrawal
    User1->>GroupSavings: withdraw(group_id, user1, 500)
    GroupSavings->>LendingPool: withdraw(500, GroupSavings, GroupSavings)
    LendingPool-->>GroupSavings: Assets received
    GroupSavings->>ERC20: transfer(user1, 500)
    GroupSavings->>GroupSavings: Update group_total_deposited: 1000
    GroupSavings-->>User1: Withdrawal
```

## Key Design Patterns

### 1. Token Approval Pattern
All contracts require users to approve token spending before deposits:
```
User → ERC20.approve(contract, amount) → Contract.deposit(...)
```

### 2. Authorized Caller Pattern
YieldManager uses an authorization system to allow only trusted contracts to deposit:
```
Admin → YieldManager.set_authorized_caller(contract, true)
AuthorizedContract → YieldManager.deposit(from, user, amount)
```

### 3. Yield Distribution Pattern
YieldManager calculates yield from lending pool and distributes proportionally:
```
YieldManager → LendingPool.total_assets() → Calculate yield
→ For each user: (yield * user_balance) / total_deposited
→ Apply bonuses/penalties → Update user yield
```

### 4. Group Membership Validation
GroupSavings validates membership before allowing operations:
```
User → GroupSavings.save(group_id, member, amount)
→ Validate: group exists, caller == member, member in group
```

### 5. Goal Completion Pattern
IndividualSavings automatically completes goals when target is reached:
```
User → IndividualSavings.deposit(goal_id, amount)
→ Update current_amount
→ If current_amount >= target_amount: complete_goal()
```

## Security Considerations

1. **Access Control**: All contracts use admin/owner checks for configuration
2. **Input Validation**: All functions validate inputs (non-zero amounts, valid addresses, etc.)
3. **Balance Checks**: Withdrawals always check sufficient balance before transfer
4. **Authorization**: YieldManager requires explicit authorization for deposits
5. **Group Validation**: GroupSavings validates membership before operations
6. **Goal Ownership**: IndividualSavings verifies goal ownership for all operations

