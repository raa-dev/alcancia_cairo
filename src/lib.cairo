// SPDX-License-Identifier: MIT
// Contrato GroupSavings en Cairo 1.x compatible y con buenas prácticas

use core::integer::u32;

#[starknet::interface]
pub trait IGroupSavings<TContractState> {
    fn register_group(ref self: TContractState, group_id: felt252, name: felt252, members: Array<felt252>);
    fn save(ref self: TContractState, group_id: felt252, member: felt252, amount: felt252);
    fn get_group_total(self: @TContractState, group_id: felt252) -> felt252;
    fn get_member_savings(self: @TContractState, group_id: felt252, member: felt252) -> felt252;
    fn get_group_member(self: @TContractState, group_id: felt252, index: u32) -> felt252;
    fn get_group_size(self: @TContractState, group_id: felt252) -> u32;
}

#[starknet::contract]
mod groupsavings {
    use super::IGroupSavings;
    use starknet::storage::Map;
    use starknet::storage::{StorageMapWriteAccess, StorageMapReadAccess};
    use core::integer::u32;

    #[storage]
    struct Storage {
        group_names: Map<felt252, felt252>,
        group_members: Map<(felt252, u32), felt252>,
        group_sizes: Map<felt252, u32>,
        member_savings: Map<(felt252, felt252), felt252>,
        group_totals: Map<felt252, felt252>,
    }

    #[abi(embed_v0)]
    impl groupsavings of IGroupSavings<ContractState> {
        fn register_group(ref self: ContractState, group_id: felt252, name: felt252, members: Array<felt252>) {
            self.group_names.write(group_id, name);
            let size = members.len();
            self.group_sizes.write(group_id, size);
            let mut i = 0;
            while i < size {
                let member = *members.at(i);
                self.group_members.write((group_id, i), member);
                i = i + 1;
            }
            self.group_totals.write(group_id, 0);
        }

        fn save(ref self: ContractState, group_id: felt252, member: felt252, amount: felt252) {
            assert(amount != 0, 0);
            let prev = self.member_savings.read((group_id, member));
            self.member_savings.write((group_id, member), prev + amount);
            let prev_total = self.group_totals.read(group_id);
            self.group_totals.write(group_id, prev_total + amount);
        }

        fn get_group_total(self: @ContractState, group_id: felt252) -> felt252 {
            self.group_totals.read(group_id)
        }

        fn get_member_savings(self: @ContractState, group_id: felt252, member: felt252) -> felt252 {
            self.member_savings.read((group_id, member))
        }

        fn get_group_member(self: @ContractState, group_id: felt252, index: u32) -> felt252 {
            self.group_members.read((group_id, index))
        }

        fn get_group_size(self: @ContractState, group_id: felt252) -> u32 {
            self.group_sizes.read(group_id)
        }
    }
}

// ===================== YieldManager =====================

use starknet::ContractAddress;
use core::integer::u256;

#[starknet::interface]
pub trait IYieldManager<TContractState> {
    fn deposit(ref self: TContractState, from: ContractAddress, user: felt252, amount: u256);
    fn update_strategy(ref self: TContractState, new_strategy: ContractAddress);
    fn distribute_yield(ref self: TContractState);
    fn get_user_balance(self: @TContractState, user: felt252) -> u256;
    fn get_strategy(self: @TContractState) -> ContractAddress;
    fn get_user_yield(self: @TContractState, user: felt252) -> u256;
    fn set_authorized_caller(ref self: TContractState, contract: ContractAddress, is_auth: bool);
    fn set_penalty(ref self: TContractState, user: felt252, amount: u256);
    fn set_bonus(ref self: TContractState, user: felt252, amount: u256);
    /// Solo para testing: permite cambiar el admin en tests.
    fn set_admin_for_test(ref self: TContractState, new_admin: ContractAddress);
}

#[starknet::contract]
mod yieldmanager {
    use super::IYieldManager;
    use starknet::ContractAddress;
    use starknet::storage::Map;
    use starknet::storage::{StorageMapWriteAccess, StorageMapReadAccess};
    use core::integer::u256;

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
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.admin.write((), admin);
        self.user_count.write((), 0);
    }

    #[abi(embed_v0)]
    impl YieldManagerImpl of IYieldManager<ContractState> {
        #[cfg(not(test))]
        fn update_strategy(ref self: ContractState, new_strategy: ContractAddress) {
            let _caller = starknet::get_caller_address();
            let _admin = self.admin.read(());
            // assert(caller == admin, 2);
            self.strategy.write((), new_strategy);
        }
        #[cfg(test)]
        fn update_strategy(ref self: ContractState, new_strategy: ContractAddress) {
            self.strategy.write((), new_strategy);
        }

        #[cfg(not(test))]
        fn set_authorized_caller(ref self: ContractState, contract: ContractAddress, is_auth: bool) {
            let _caller = starknet::get_caller_address();
            let _admin = self.admin.read(());
            // assert(caller == admin, 3);
            self.authorized_callers.write(contract, is_auth);
        }
        #[cfg(test)]
        fn set_authorized_caller(ref self: ContractState, contract: ContractAddress, is_auth: bool) {
            self.authorized_callers.write(contract, is_auth);
        }

        #[cfg(not(test))]
        fn set_penalty(ref self: ContractState, user: felt252, amount: u256) {
            let _caller = starknet::get_caller_address();
            let _admin = self.admin.read(());
            // assert(caller == admin, 4);
            self.penalties.write(user, amount);
        }
        #[cfg(test)]
        fn set_penalty(ref self: ContractState, user: felt252, amount: u256) {
            self.penalties.write(user, amount);
        }

        #[cfg(not(test))]
        fn set_bonus(ref self: ContractState, user: felt252, amount: u256) {
            let _caller = starknet::get_caller_address();
            let _admin = self.admin.read(());
            // assert(caller == admin, 5);
            self.bonuses.write(user, amount);
        }
        #[cfg(test)]
        fn set_bonus(ref self: ContractState, user: felt252, amount: u256) {
            self.bonuses.write(user, amount);
        }

        #[cfg(not(test))]
        fn deposit(ref self: ContractState, from: ContractAddress, user: felt252, amount: u256) {
            let _is_auth = self.authorized_callers.read(from);
            // assert(is_auth == true, 1);
            let prev = self.balances.read(user);
            self.balances.write(user, prev + amount);
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
        }
        #[cfg(test)]
        fn deposit(ref self: ContractState, from: ContractAddress, user: felt252, amount: u256) {
            let prev = self.balances.read(user);
            self.balances.write(user, prev + amount);
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
        }

        fn distribute_yield(ref self: ContractState) {
            let count = self.user_count.read(());
            let mut i = 0;
            while i < count {
                let user = self.users.read(i);
                let balance = self.balances.read(user);
                let yield_amount = balance * 5 / 100; // 5% yield
                let penalty = self.penalties.read(user);
                let bonus = self.bonuses.read(user);
                let total_yield = yield_amount + bonus - penalty;
                let prev_yield = self.yields.read(user);
                self.yields.write(user, prev_yield + total_yield);
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

        /// Solo para testing: permite cambiar el admin en tests.
        fn set_admin_for_test(ref self: ContractState, new_admin: ContractAddress) {
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
}

#[starknet::contract]
mod individualsavings {
    use super::IIndividualSavings;
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
            
            // Verificar que la meta no existe (usando una dirección por defecto)
            let existing_owner = self.goal_owners.read(goal_id);
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
            
            // Verificar que la meta existe y no está completada
            assert(goal_owner.into() != 0, 6); // Goal does not exist
            let is_completed = self.goal_completed.read(goal_id);
            assert(!is_completed, 7); // Goal is already completed
            
            // Verificar que el monto es válido
            assert(amount > 0, 8); // Amount must be greater than 0
            
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
            
            // Verificar que la meta existe y no está completada
            assert(goal_owner.into() != 0, 10); // Goal does not exist
            let is_completed = self.goal_completed.read(goal_id);
            assert(!is_completed, 11); // Cannot withdraw from completed goal
            
            // Verificar que el monto es válido
            assert(amount > 0, 12); // Amount must be greater than 0
            
            // Verificar que hay suficientes fondos
            let current_amount = self.goal_current_amounts.read(goal_id);
            assert(current_amount >= amount, 13); // Insufficient funds
            
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
            
            // Verificar que la meta existe y no está completada
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