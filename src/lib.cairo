// SPDX-License-Identifier: MIT
// Contrato GroupSavings en Cairo 1.x compatible y con buenas prácticas

use core::integer::u32;
use core::integer::u256;
use starknet::ContractAddress;

// ERC20 Interface
#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

#[starknet::interface]
pub trait IGroupSavings<TContractState> {
    fn register_group(ref self: TContractState, group_id: felt252, name: felt252, members: Array<felt252>);
    fn save(ref self: TContractState, group_id: felt252, member: felt252, amount: u256);
    fn withdraw(ref self: TContractState, group_id: felt252, member: felt252, amount: u256);
    fn get_group_total(self: @TContractState, group_id: felt252) -> u256;
    fn get_member_savings(self: @TContractState, group_id: felt252, member: felt252) -> u256;
    fn get_group_member(self: @TContractState, group_id: felt252, index: u32) -> felt252;
    fn get_group_size(self: @TContractState, group_id: felt252) -> u32;
    fn is_group_member(self: @TContractState, group_id: felt252, member: felt252) -> bool;
    fn set_token_address(ref self: TContractState, token_address: ContractAddress);
    fn get_token_address(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod groupsavings {
    use super::{IGroupSavings, IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::Map;
    use starknet::storage::{StorageMapWriteAccess, StorageMapReadAccess};
    use core::integer::u32;
    use core::integer::u256;
    use core::array::ArrayTrait;
    use core::traits::TryInto;

    #[storage]
    struct Storage {
        group_names: Map<felt252, felt252>,
        group_members: Map<(felt252, u32), felt252>,
        group_sizes: Map<felt252, u32>,
        member_savings: Map<(felt252, felt252), u256>,
        group_totals: Map<felt252, u256>,
        group_creators: Map<felt252, ContractAddress>,
        group_registered: Map<felt252, bool>,
        token_address: Map<(), ContractAddress>,
        admin: Map<(), ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GroupRegistered: GroupRegistered,
        SavingsDeposited: SavingsDeposited,
        Withdrawal: Withdrawal,
        TokenAddressSet: TokenAddressSet,
    }

    #[derive(Drop, starknet::Event)]
    struct GroupRegistered {
        group_id: felt252,
        creator: ContractAddress,
        name: felt252,
        member_count: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct SavingsDeposited {
        group_id: felt252,
        member: felt252,
        amount: u256,
        new_total: u256,
        member_total: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawal {
        group_id: felt252,
        member: felt252,
        amount: u256,
        new_total: u256,
        member_total: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TokenAddressSet {
        token_address: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write((), admin);
    }

    #[abi(embed_v0)]
    impl groupsavings of IGroupSavings<ContractState> {
        fn register_group(ref self: ContractState, group_id: felt252, name: felt252, members: Array<felt252>) {
            // Validate inputs
            assert(name != 0, 1); // Name cannot be empty
            let size = members.len();
            assert(size > 0, 2); // Group must have at least one member
            
            // Check if group already exists
            let exists = self.group_registered.read(group_id);
            assert(!exists, 3); // Group already exists
            
            // Validate group_id is not zero
            assert(group_id != 0, 4); // Invalid group_id
            
            // Register group
            let caller = starknet::get_caller_address();
            self.group_registered.write(group_id, true);
            self.group_creators.write(group_id, caller);
            self.group_names.write(group_id, name);
            self.group_sizes.write(group_id, size);
            
            // Register members and validate no duplicates
            let mut i = 0;
            while i < size {
                let member = *members.at(i);
                assert(member != 0, 5); // Invalid member address
                
                // Check for duplicate members
                let mut j = 0;
                while j < i {
                    let prev_member = *members.at(j);
                    assert(member != prev_member, 6); // Duplicate member
                    j = j + 1;
                }
                
                self.group_members.write((group_id, i), member);
                i = i + 1;
            }
            self.group_totals.write(group_id, 0);
            
            // Emit event
            self.emit(GroupRegistered {
                group_id,
                creator: caller,
                name,
                member_count: size,
            });
        }

        fn save(ref self: ContractState, group_id: felt252, member: felt252, amount: u256) {
            // Validate inputs
            assert(amount != 0, 7); // Amount must be greater than 0
            assert(group_id != 0, 8); // Invalid group_id
            assert(member != 0, 9); // Invalid member
            
            // Verify group exists
            let exists = self.group_registered.read(group_id);
            assert(exists, 10); // Group does not exist
            
            // Verify caller is the member
            let caller = starknet::get_caller_address();
            assert(caller.into() == member, 11); // Only the member can save for themselves
            
            // Verify member is part of the group
            let is_member = self.is_group_member(group_id, member);
            assert(is_member, 12); // Member is not part of this group
            
            // Transfer tokens from member to contract
            let token_address = self.token_address.read(());
            assert(token_address.into() != 0, 14); // Token address not set
            let token = IERC20Dispatcher { contract_address: token_address };
            let sender = starknet::get_caller_address();
            let self_address = starknet::get_contract_address();
            token.transfer_from(sender, self_address, amount);
            
            // Perform the save operation
            let prev = self.member_savings.read((group_id, member));
            let new_member_total = prev + amount;
            self.member_savings.write((group_id, member), new_member_total);
            
            let prev_total = self.group_totals.read(group_id);
            let new_total = prev_total + amount;
            self.group_totals.write(group_id, new_total);
            
            // Emit event
            self.emit(SavingsDeposited {
                group_id,
                member,
                amount,
                new_total,
                member_total: new_member_total,
            });
        }

        fn withdraw(ref self: ContractState, group_id: felt252, member: felt252, amount: u256) {
            // Validate inputs
            assert(amount != 0, 15); // Amount must be greater than 0
            assert(group_id != 0, 16); // Invalid group_id
            assert(member != 0, 17); // Invalid member
            
            // Verify group exists
            let exists = self.group_registered.read(group_id);
            assert(exists, 18); // Group does not exist
            
            // Verify caller is the member
            let caller = starknet::get_caller_address();
            assert(caller.into() == member, 19); // Only the member can withdraw
            
            // Verify member is part of the group
            let is_member = self.is_group_member(group_id, member);
            assert(is_member, 20); // Member is not part of this group
            
            // Check sufficient balance
            let current_savings = self.member_savings.read((group_id, member));
            assert(current_savings >= amount, 21); // Insufficient savings
            
            // Transfer tokens from contract to member
            let token_address = self.token_address.read(());
            assert(token_address.into() != 0, 22); // Token address not set
            let token = IERC20Dispatcher { contract_address: token_address };
            let member_address: ContractAddress = member.try_into().unwrap();
            token.transfer(member_address, amount);
            
            // Update balances
            let new_member_total = current_savings - amount;
            self.member_savings.write((group_id, member), new_member_total);
            
            let prev_total = self.group_totals.read(group_id);
            let new_total = prev_total - amount;
            self.group_totals.write(group_id, new_total);
            
            // Emit event
            self.emit(Withdrawal {
                group_id,
                member,
                amount,
                new_total,
                member_total: new_member_total,
            });
        }

        fn get_group_total(self: @ContractState, group_id: felt252) -> u256 {
            self.group_totals.read(group_id)
        }

        fn get_member_savings(self: @ContractState, group_id: felt252, member: felt252) -> u256 {
            self.member_savings.read((group_id, member))
        }

        fn get_group_member(self: @ContractState, group_id: felt252, index: u32) -> felt252 {
            let size = self.group_sizes.read(group_id);
            assert(index < size, 13); // Index out of bounds
            self.group_members.read((group_id, index))
        }

        fn get_group_size(self: @ContractState, group_id: felt252) -> u32 {
            self.group_sizes.read(group_id)
        }

        fn is_group_member(self: @ContractState, group_id: felt252, member: felt252) -> bool {
            let size = self.group_sizes.read(group_id);
            let mut i = 0;
            while i < size {
                let group_member = self.group_members.read((group_id, i));
                if group_member == member {
                    return true;
                }
                i = i + 1;
            };
            false
        }

        fn set_token_address(ref self: ContractState, token_address: ContractAddress) {
            let caller = starknet::get_caller_address();
            let admin = self.admin.read(());
            assert(caller == admin, 23); // Only admin can set token address
            assert(token_address.into() != 0, 24); // Invalid token address
            self.token_address.write((), token_address);
            self.emit(TokenAddressSet { token_address });
        }

        fn get_token_address(self: @ContractState) -> ContractAddress {
            self.token_address.read(())
        }
    }
}

// ===================== YieldManager =====================

#[starknet::interface]
pub trait IYieldManager<TContractState> {
    fn deposit(ref self: TContractState, from: ContractAddress, user: felt252, amount: u256);
    fn withdraw(ref self: TContractState, user: felt252, amount: u256);
    fn update_strategy(ref self: TContractState, new_strategy: ContractAddress);
    fn distribute_yield(ref self: TContractState);
    fn get_user_balance(self: @TContractState, user: felt252) -> u256;
    fn get_strategy(self: @TContractState) -> ContractAddress;
    fn get_user_yield(self: @TContractState, user: felt252) -> u256;
    fn set_authorized_caller(ref self: TContractState, contract: ContractAddress, is_auth: bool);
    fn set_penalty(ref self: TContractState, user: felt252, amount: u256);
    fn set_bonus(ref self: TContractState, user: felt252, amount: u256);
    fn set_token_address(ref self: TContractState, token_address: ContractAddress);
    fn get_token_address(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod yieldmanager {
    use super::{IYieldManager, IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::Map;
    use starknet::storage::{StorageMapWriteAccess, StorageMapReadAccess};
    use core::integer::u256;
    use core::traits::TryInto;

    #[storage]
    struct Storage {
        balances: Map<felt252, u256>,
        yields: Map<felt252, u256>,
        authorized_callers: Map<ContractAddress, bool>,
        strategy: Map<(), ContractAddress>,
        admin: Map<(), ContractAddress>,
        penalties: Map<felt252, u256>,
        bonuses: Map<felt252, u256>,
        users: Map<u32, felt252>, // Para iterar usuarios
        user_count: Map<(), u32>,
        token_address: Map<(), ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdrawal: Withdrawal,
        YieldDistributed: YieldDistributed,
        StrategyUpdated: StrategyUpdated,
        AuthorizedCallerSet: AuthorizedCallerSet,
        PenaltySet: PenaltySet,
        BonusSet: BonusSet,
        TokenAddressSet: TokenAddressSet,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        from: ContractAddress,
        user: felt252,
        amount: u256,
        new_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct YieldDistributed {
        user: felt252,
        yield_amount: u256,
        total_yield: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct StrategyUpdated {
        new_strategy: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct AuthorizedCallerSet {
        contract: ContractAddress,
        is_authorized: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct PenaltySet {
        user: felt252,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct BonusSet {
        user: felt252,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawal {
        user: felt252,
        amount: u256,
        new_balance: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TokenAddressSet {
        token_address: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write((), admin);
        self.user_count.write((), 0);
    }

    #[abi(embed_v0)]
    impl YieldManagerImpl of IYieldManager<ContractState> {
        fn update_strategy(ref self: ContractState, new_strategy: ContractAddress) {
            let caller = starknet::get_caller_address();
            let admin = self.admin.read(());
            assert(caller == admin, 2); // Only admin can update strategy
            assert(new_strategy.into() != 0, 20); // Invalid strategy address
            self.strategy.write((), new_strategy);
            self.emit(StrategyUpdated { new_strategy });
        }

        fn set_authorized_caller(ref self: ContractState, contract: ContractAddress, is_auth: bool) {
            let caller = starknet::get_caller_address();
            let admin = self.admin.read(());
            assert(caller == admin, 3); // Only admin can set authorized callers
            assert(contract.into() != 0, 21); // Invalid contract address
            self.authorized_callers.write(contract, is_auth);
            self.emit(AuthorizedCallerSet { contract, is_authorized: is_auth });
        }

        fn set_penalty(ref self: ContractState, user: felt252, amount: u256) {
            let caller = starknet::get_caller_address();
            let admin = self.admin.read(());
            assert(caller == admin, 4); // Only admin can set penalties
            assert(user != 0, 22); // Invalid user
            self.penalties.write(user, amount);
            self.emit(PenaltySet { user, amount });
        }

        fn set_bonus(ref self: ContractState, user: felt252, amount: u256) {
            let caller = starknet::get_caller_address();
            let admin = self.admin.read(());
            assert(caller == admin, 5); // Only admin can set bonuses
            assert(user != 0, 23); // Invalid user
            self.bonuses.write(user, amount);
            self.emit(BonusSet { user, amount });
        }

        fn deposit(ref self: ContractState, from: ContractAddress, user: felt252, amount: u256) {
            // Validate inputs
            assert(amount != 0, 24); // Amount must be greater than 0
            assert(user != 0, 25); // Invalid user
            assert(from.into() != 0, 26); // Invalid from address
            
            let is_auth = self.authorized_callers.read(from);
            assert(is_auth, 1); // Caller is not authorized
            
            // Transfer tokens from authorized caller to contract
            let token_address = self.token_address.read(());
            assert(token_address.into() != 0, 27); // Token address not set
            let token = IERC20Dispatcher { contract_address: token_address };
            let self_address = starknet::get_contract_address();
            token.transfer_from(from, self_address, amount);
            
            let prev = self.balances.read(user);
            let new_balance = prev + amount;
            self.balances.write(user, new_balance);
            
            // Registrar usuario si es nuevo
            let mut found = false;
            let count = self.user_count.read(());
            let mut i = 0;
            while i < count {
                if self.users.read(i) == user {
                    found = true;
                    break;
                }
                i = i + 1;
            }
            if !found {
                self.users.write(count, user);
                self.user_count.write((), count + 1);
            }
            
            // Emit event
            self.emit(Deposit {
                from,
                user,
                amount,
                new_balance,
            });
        }

        fn withdraw(ref self: ContractState, user: felt252, amount: u256) {
            // Validate inputs
            assert(amount != 0, 28); // Amount must be greater than 0
            assert(user != 0, 29); // Invalid user
            
            // Check sufficient balance
            let current_balance = self.balances.read(user);
            assert(current_balance >= amount, 30); // Insufficient balance
            
            // Transfer tokens from contract to user
            let token_address = self.token_address.read(());
            assert(token_address.into() != 0, 31); // Token address not set
            let token = IERC20Dispatcher { contract_address: token_address };
            let user_address: ContractAddress = user.try_into().unwrap();
            token.transfer(user_address, amount);
            
            // Update balance
            let new_balance = current_balance - amount;
            self.balances.write(user, new_balance);
            
            // Emit event
            self.emit(Withdrawal {
                user,
                amount,
                new_balance,
            });
        }

        fn distribute_yield(ref self: ContractState) {
            let count = self.user_count.read(());
            let mut i = 0;
            while i < count {
                let user = self.users.read(i);
                let balance = self.balances.read(user);
                
                // Only calculate yield if user has balance
                if balance > 0 {
                    let yield_amount = balance * 5 / 100; // 5% yield
                    let penalty = self.penalties.read(user);
                    let bonus = self.bonuses.read(user);
                    
                    // Calculate total yield (handle underflow if penalty > yield_amount + bonus)
                    let base_yield = yield_amount + bonus;
                    let total_yield = if base_yield >= penalty {
                        base_yield - penalty
                    } else {
                        0
                    };
                    
                    if total_yield > 0 {
                        let prev_yield = self.yields.read(user);
                        let new_total_yield = prev_yield + total_yield;
                        self.yields.write(user, new_total_yield);
                        
                        // Emit event
                        self.emit(YieldDistributed {
                            user,
                            yield_amount: total_yield,
                            total_yield: new_total_yield,
                        });
                    }
                }
                
                // Reset penalties and bonuses after distribution
                self.penalties.write(user, 0);
                self.bonuses.write(user, 0);
                i = i + 1;
            }
        }

        fn get_user_balance(self: @ContractState, user: felt252) -> u256 {
            self.balances.read(user)
        }

        fn get_strategy(self: @ContractState) -> ContractAddress {
            self.strategy.read(())
        }

        fn get_user_yield(self: @ContractState, user: felt252) -> u256 {
            self.yields.read(user)
        }

        fn set_token_address(ref self: ContractState, token_address: ContractAddress) {
            let caller = starknet::get_caller_address();
            let admin = self.admin.read(());
            assert(caller == admin, 32); // Only admin can set token address
            assert(token_address.into() != 0, 33); // Invalid token address
            self.token_address.write((), token_address);
            self.emit(TokenAddressSet { token_address });
        }

        fn get_token_address(self: @ContractState) -> ContractAddress {
            self.token_address.read(())
        }
    }
    
    // Internal implementation for testing only
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn set_admin_for_test(ref self: ContractState, new_admin: ContractAddress) {
            // This function should only be used in tests
            // In production, admin can only be changed through proper ownership transfer
            self.admin.write((), new_admin);
        }
    }
}

// ===================== IndividualSavings =====================

use core::integer::u64;

#[starknet::interface]
pub trait IIndividualSavings<TContractState> {
    // Funciones principales
    fn create_savings_goal(
        ref self: TContractState,
        goal_id: felt252,
        target_amount: u256,
        deadline: u64,
        description: felt252
    );
    fn deposit(ref self: TContractState, goal_id: felt252, amount: u256);
    fn withdraw(ref self: TContractState, goal_id: felt252, amount: u256);
    fn complete_goal(ref self: TContractState, goal_id: felt252);
    
    // Funciones de consulta
    fn get_goal_info(self: @TContractState, goal_id: felt252) -> (felt252, u256, u64, felt252, u256, u64, bool);
    fn get_goal_progress(self: @TContractState, goal_id: felt252) -> (u256, u256, u64);
    fn get_user_goals(self: @TContractState, user: felt252) -> Array<felt252>;
    fn get_goal_count(self: @TContractState, user: felt252) -> u32;
    
    // Funciones de penalización y bonificación
    fn apply_penalty(ref self: TContractState, goal_id: felt252, penalty_amount: u256);
    fn apply_bonus(ref self: TContractState, goal_id: felt252, bonus_amount: u256);
    fn get_penalties(self: @TContractState, goal_id: felt252) -> u256;
    fn get_bonuses(self: @TContractState, goal_id: felt252) -> u256;
    
    // Funciones administrativas
    fn set_owner(ref self: TContractState, new_owner: ContractAddress);
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn set_token_address(ref self: TContractState, token_address: ContractAddress);
    fn get_token_address(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod individualsavings {
    use super::{IIndividualSavings, IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::Map;
    use starknet::storage::{StorageMapWriteAccess, StorageMapReadAccess};
    use core::integer::u256;
    use core::integer::u64;
    use core::integer::u32;
    use core::array::ArrayTrait;

    #[storage]
    struct Storage {
        // Información de metas de ahorro
        goal_owners: Map<felt252, ContractAddress>,
        goal_targets: Map<felt252, u256>,
        goal_deadlines: Map<felt252, u64>,
        goal_descriptions: Map<felt252, felt252>,
        goal_current_amounts: Map<felt252, u256>,
        goal_created_at: Map<felt252, u64>,
        goal_completed: Map<felt252, bool>,
        
        // Penalizaciones y bonificaciones
        goal_penalties: Map<felt252, u256>,
        goal_bonuses: Map<felt252, u256>,
        
        // Gestión de usuarios
        user_goals: Map<(felt252, u32), felt252>,
        user_goal_counts: Map<felt252, u32>,
        
        // Owner del contrato
        owner: Map<(), ContractAddress>,
        
        // Token address
        token_address: Map<(), ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GoalCreated: GoalCreated,
        Deposit: Deposit,
        Withdrawal: Withdrawal,
        GoalCompleted: GoalCompleted,
        PenaltyApplied: PenaltyApplied,
        BonusApplied: BonusApplied,
        ProgressUpdated: ProgressUpdated,
        TokenAddressSet: TokenAddressSet,
    }

    #[derive(Drop, starknet::Event)]
    struct GoalCreated {
        goal_id: felt252,
        owner: ContractAddress,
        target_amount: u256,
        deadline: u64,
        description: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        goal_id: felt252,
        amount: u256,
        current_total: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawal {
        goal_id: felt252,
        amount: u256,
        current_total: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct GoalCompleted {
        goal_id: felt252,
        final_amount: u256,
        completed_at: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct PenaltyApplied {
        goal_id: felt252,
        penalty_amount: u256,
        reason: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct BonusApplied {
        goal_id: felt252,
        bonus_amount: u256,
        reason: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct ProgressUpdated {
        goal_id: felt252,
        current_amount: u256,
        target_amount: u256,
        progress_percentage: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TokenAddressSet {
        token_address: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write((), owner);
    }

    #[abi(embed_v0)]
    impl IndividualSavingsImpl of IIndividualSavings<ContractState> {
        fn create_savings_goal(
            ref self: ContractState,
            goal_id: felt252,
            target_amount: u256,
            deadline: u64,
            description: felt252
        ) {
            // Verificar que el caller es el owner (wallet invisible)
            let caller = starknet::get_caller_address();
            let owner = self.owner.read(());
            assert(caller == owner, 1); // Only owner can create goals
            
            // Verificar que la meta no existe
            let existing_owner = self.goal_owners.read(goal_id);
            // Check if goal already exists by verifying owner is zero address (meaning it doesn't exist)
            assert(existing_owner.into() == 0, 2); // Goal already exists
            
            // Verificar que el monto objetivo es válido
            assert(target_amount > 0, 3); // Target amount must be greater than 0
            
            // Verificar que la fecha límite es futura
            let current_time = starknet::get_block_timestamp();
            assert(deadline > current_time, 4); // Deadline must be in the future
            
            // Crear la meta
            self.goal_owners.write(goal_id, caller);
            self.goal_targets.write(goal_id, target_amount);
            self.goal_deadlines.write(goal_id, deadline);
            self.goal_descriptions.write(goal_id, description);
            self.goal_current_amounts.write(goal_id, 0);
            self.goal_created_at.write(goal_id, current_time);
            self.goal_completed.write(goal_id, false);
            self.goal_penalties.write(goal_id, 0);
            self.goal_bonuses.write(goal_id, 0);
            
            // Registrar la meta para el usuario
            let user_goal_count = self.user_goal_counts.read(caller.into());
            self.user_goals.write((caller.into(), user_goal_count), goal_id);
            self.user_goal_counts.write(caller.into(), user_goal_count + 1);
            
            // Emitir evento
            self.emit(GoalCreated {
                goal_id,
                owner: caller,
                target_amount,
                deadline,
                description,
            });
        }

        fn deposit(ref self: ContractState, goal_id: felt252, amount: u256) {
            // Verificar que el caller es el owner de la meta
            let caller = starknet::get_caller_address();
            let goal_owner = self.goal_owners.read(goal_id);
            assert(caller == goal_owner, 5); // Only goal owner can deposit
            
            // Verificar que la meta existe
            assert(goal_owner.into() != 0, 6); // Goal does not exist
            let is_completed = self.goal_completed.read(goal_id);
            assert(!is_completed, 7); // Goal is already completed
            
            // Verificar que el monto es válido
            assert(amount > 0, 8); // Amount must be greater than 0
            
            // Transfer tokens from user to contract
            let token_address = self.token_address.read(());
            assert(token_address.into() != 0, 25); // Token address not set
            let token = IERC20Dispatcher { contract_address: token_address };
            let self_address = starknet::get_contract_address();
            token.transfer_from(caller, self_address, amount);
            
            // Realizar el depósito
            let current_amount = self.goal_current_amounts.read(goal_id);
            let new_amount = current_amount + amount;
            self.goal_current_amounts.write(goal_id, new_amount);
            
            // Emitir evento
            self.emit(Deposit {
                goal_id,
                amount,
                current_total: new_amount,
            });
            
            // Emitir evento de progreso
            let target_amount = self.goal_targets.read(goal_id);
            let progress_percentage = (new_amount * 100) / target_amount;
            self.emit(ProgressUpdated {
                goal_id,
                current_amount: new_amount,
                target_amount,
                progress_percentage,
            });
            
            // Verificar si la meta se completó
            if new_amount >= target_amount {
                self.complete_goal_internal(goal_id);
            }
        }

        fn withdraw(ref self: ContractState, goal_id: felt252, amount: u256) {
            // Verificar que el caller es el owner de la meta
            let caller = starknet::get_caller_address();
            let goal_owner = self.goal_owners.read(goal_id);
            assert(caller == goal_owner, 9); // Only goal owner can withdraw
            
            // Verificar que la meta existe
            assert(goal_owner.into() != 0, 10); // Goal does not exist
            let is_completed = self.goal_completed.read(goal_id);
            assert(!is_completed, 11); // Cannot withdraw from completed goal
            
            // Verificar que el monto es válido
            assert(amount > 0, 12); // Amount must be greater than 0
            
            // Verificar que hay suficientes fondos
            let current_amount = self.goal_current_amounts.read(goal_id);
            assert(current_amount >= amount, 13); // Insufficient funds
            
            // Transfer tokens from contract to user
            let token_address = self.token_address.read(());
            assert(token_address.into() != 0, 26); // Token address not set
            let token = IERC20Dispatcher { contract_address: token_address };
            token.transfer(caller, amount);
            
            // Realizar el retiro
            let new_amount = current_amount - amount;
            self.goal_current_amounts.write(goal_id, new_amount);
            
            // Emitir evento
            self.emit(Withdrawal {
                goal_id,
                amount,
                current_total: new_amount,
            });
            
            // Emitir evento de progreso
            let target_amount = self.goal_targets.read(goal_id);
            // Safe division: target_amount is validated to be > 0 in create_savings_goal
            assert(target_amount > 0, 24); // Target amount must be valid
            let progress_percentage = (new_amount * 100) / target_amount;
            self.emit(ProgressUpdated {
                goal_id,
                current_amount: new_amount,
                target_amount,
                progress_percentage,
            });
        }

        fn complete_goal(ref self: ContractState, goal_id: felt252) {
            // Verificar que el caller es el owner de la meta
            let caller = starknet::get_caller_address();
            let goal_owner = self.goal_owners.read(goal_id);
            assert(caller == goal_owner, 14); // Only goal owner can complete goal
            
            // Verificar que la meta existe
            assert(goal_owner.into() != 0, 15); // Goal does not exist
            let is_completed = self.goal_completed.read(goal_id);
            assert(!is_completed, 16); // Goal is already completed
            
            // Verificar que se alcanzó el objetivo
            let current_amount = self.goal_current_amounts.read(goal_id);
            let target_amount = self.goal_targets.read(goal_id);
            assert(current_amount >= target_amount, 17); // Goal target not reached
            
            self.complete_goal_internal(goal_id);
        }

        fn get_goal_info(
            self: @ContractState,
            goal_id: felt252
        ) -> (felt252, u256, u64, felt252, u256, u64, bool) {
            let owner = self.goal_owners.read(goal_id);
            let target_amount = self.goal_targets.read(goal_id);
            let deadline = self.goal_deadlines.read(goal_id);
            let description = self.goal_descriptions.read(goal_id);
            let current_amount = self.goal_current_amounts.read(goal_id);
            let created_at = self.goal_created_at.read(goal_id);
            let is_completed = self.goal_completed.read(goal_id);
            
            (owner.into(), target_amount, deadline, description, current_amount, created_at, is_completed)
        }

        fn get_goal_progress(
            self: @ContractState,
            goal_id: felt252
        ) -> (u256, u256, u64) {
            let current_amount = self.goal_current_amounts.read(goal_id);
            let target_amount = self.goal_targets.read(goal_id);
            let deadline = self.goal_deadlines.read(goal_id);
            
            (current_amount, target_amount, deadline)
        }

        fn get_user_goals(self: @ContractState, user: felt252) -> Array<felt252> {
            let goal_count = self.user_goal_counts.read(user);
            let mut goals = ArrayTrait::new();
            let mut i = 0;
            while i < goal_count {
                let goal_id = self.user_goals.read((user, i));
                goals.append(goal_id);
                i = i + 1;
            };
            goals
        }

        fn get_goal_count(self: @ContractState, user: felt252) -> u32 {
            self.user_goal_counts.read(user)
        }

        fn apply_penalty(ref self: ContractState, goal_id: felt252, penalty_amount: u256) {
            // Verificar que el caller es el owner de la meta
            let caller = starknet::get_caller_address();
            let goal_owner = self.goal_owners.read(goal_id);
            assert(caller == goal_owner, 18); // Only goal owner can apply penalties
            
            // Verificar que la meta existe
            assert(goal_owner.into() != 0, 19); // Goal does not exist
            
            // Aplicar penalización
            let current_penalty = self.goal_penalties.read(goal_id);
            let new_penalty = current_penalty + penalty_amount;
            self.goal_penalties.write(goal_id, new_penalty);
            
            // Emitir evento
            self.emit(PenaltyApplied {
                goal_id,
                penalty_amount,
                reason: 'Manual penalty applied',
            });
        }

        fn apply_bonus(ref self: ContractState, goal_id: felt252, bonus_amount: u256) {
            // Verificar que el caller es el owner de la meta
            let caller = starknet::get_caller_address();
            let goal_owner = self.goal_owners.read(goal_id);
            assert(caller == goal_owner, 20); // Only goal owner can apply bonuses
            
            // Verificar que la meta existe
            assert(goal_owner.into() != 0, 21); // Goal does not exist
            
            // Aplicar bonificación
            let current_bonus = self.goal_bonuses.read(goal_id);
            let new_bonus = current_bonus + bonus_amount;
            self.goal_bonuses.write(goal_id, new_bonus);
            
            // Emitir evento
            self.emit(BonusApplied {
                goal_id,
                bonus_amount,
                reason: 'Manual bonus applied',
            });
        }

        fn get_penalties(self: @ContractState, goal_id: felt252) -> u256 {
            self.goal_penalties.read(goal_id)
        }

        fn get_bonuses(self: @ContractState, goal_id: felt252) -> u256 {
            self.goal_bonuses.read(goal_id)
        }

        fn set_owner(ref self: ContractState, new_owner: ContractAddress) {
            // Verificar que el caller es el owner actual
            let caller = starknet::get_caller_address();
            let current_owner = self.owner.read(());
            assert(caller == current_owner, 22); // Only owner can change owner
            
            self.owner.write((), new_owner);
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read(())
        }

        fn set_token_address(ref self: ContractState, token_address: ContractAddress) {
            let caller = starknet::get_caller_address();
            let owner = self.owner.read(());
            assert(caller == owner, 27); // Only owner can set token address
            assert(token_address.into() != 0, 28); // Invalid token address
            self.token_address.write((), token_address);
            self.emit(TokenAddressSet { token_address });
        }

        fn get_token_address(self: @ContractState) -> ContractAddress {
            self.token_address.read(())
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn complete_goal_internal(ref self: ContractState, goal_id: felt252) {
            // Marcar la meta como completada
            self.goal_completed.write(goal_id, true);
            
            // Obtener información para el evento
            let current_amount = self.goal_current_amounts.read(goal_id);
            let completed_at = starknet::get_block_timestamp();
            
            // Emitir evento de completado
            self.emit(GoalCompleted {
                goal_id,
                final_amount: current_amount,
                completed_at,
            });
        }
    }
}

pub mod mock_erc20; 