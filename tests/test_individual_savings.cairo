use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address, start_cheat_block_timestamp, stop_cheat_block_timestamp};
use alcancia::IIndividualSavingsDispatcher;
use alcancia::IIndividualSavingsDispatcherTrait;
use core::array::ArrayTrait;

fn deploy_individual_savings(owner: ContractAddress) -> ContractAddress {
    let contract = declare("individualsavings").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    constructor_calldata.append(owner.into());
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

#[test]
fn test_create_goal_and_deposit() {
    let owner: ContractAddress = 1.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let goal_id: felt252 = 1;
    let target_amount: u256 = 1000;
    let current_time: u64 = 1000000;
    let deadline: u64 = current_time + 86400; // 1 day later
    let description: felt252 = 100;
    
    // Set block timestamp
    start_cheat_block_timestamp(contract_address, current_time);
    
    // Create goal as owner
    start_cheat_caller_address(contract_address, owner);
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    stop_cheat_caller_address(contract_address);
    
    // Get goal info
    let (goal_owner, target, deadline_read, desc, current, _created, completed) = dispatcher.get_goal_info(goal_id);
    assert(goal_owner == owner.into(), 0);
    assert(target == target_amount, 0);
    assert(deadline_read == deadline, 0);
    assert(desc == description, 0);
    assert(current == 0, 0);
    assert(completed == false, 0);
    
    // Deposit as owner
    start_cheat_caller_address(contract_address, owner);
    dispatcher.deposit(goal_id, 500);
    stop_cheat_caller_address(contract_address);
    
    // Verify progress
    let (current_amount, target_amount_read, _) = dispatcher.get_goal_progress(goal_id);
    assert(current_amount == 500, 0);
    assert(target_amount_read == target_amount, 0);
    
    stop_cheat_block_timestamp(contract_address);
}

#[test]
#[should_panic]
fn test_deposit_zero_should_fail() {
    let owner: ContractAddress = 2.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let goal_id: felt252 = 2;
    let target_amount: u256 = 1000;
    let current_time: u64 = 2000000;
    let deadline: u64 = current_time + 86400;
    let description: felt252 = 200;
    
    start_cheat_block_timestamp(contract_address, current_time);
    start_cheat_caller_address(contract_address, owner);
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    stop_cheat_caller_address(contract_address);
    
    // This should fail - amount must be greater than 0
    start_cheat_caller_address(contract_address, owner);
    dispatcher.deposit(goal_id, 0);
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}

#[test]
#[should_panic]
fn test_withdraw_too_much_should_fail() {
    let owner: ContractAddress = 3.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let goal_id: felt252 = 3;
    let target_amount: u256 = 1000;
    let current_time: u64 = 3000000;
    let deadline: u64 = current_time + 86400;
    let description: felt252 = 300;
    
    start_cheat_block_timestamp(contract_address, current_time);
    start_cheat_caller_address(contract_address, owner);
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    dispatcher.deposit(goal_id, 100);
    stop_cheat_caller_address(contract_address);
    
    // This should fail - insufficient funds
    start_cheat_caller_address(contract_address, owner);
    dispatcher.withdraw(goal_id, 200);
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}

#[test]
#[should_panic]
fn test_create_goal_unauthorized_should_fail() {
    let owner: ContractAddress = 4.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let unauthorized: ContractAddress = 999.try_into().unwrap();
    let goal_id: felt252 = 4;
    let target_amount: u256 = 1000;
    let current_time: u64 = 4000000;
    let deadline: u64 = current_time + 86400;
    let description: felt252 = 400;
    
    start_cheat_block_timestamp(contract_address, current_time);
    // This should fail - only owner can create goals
    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}

#[test]
#[should_panic]
fn test_deposit_unauthorized_should_fail() {
    let owner: ContractAddress = 5.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let unauthorized: ContractAddress = 888.try_into().unwrap();
    let goal_id: felt252 = 5;
    let target_amount: u256 = 1000;
    let current_time: u64 = 5000000;
    let deadline: u64 = current_time + 86400;
    let description: felt252 = 500;
    
    start_cheat_block_timestamp(contract_address, current_time);
    start_cheat_caller_address(contract_address, owner);
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    stop_cheat_caller_address(contract_address);
    
    // This should fail - only goal owner can deposit
    start_cheat_caller_address(contract_address, unauthorized);
    dispatcher.deposit(goal_id, 100);
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}

#[test]
fn test_complete_goal() {
    let owner: ContractAddress = 6.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let goal_id: felt252 = 6;
    let target_amount: u256 = 1000;
    let current_time: u64 = 6000000;
    let deadline: u64 = current_time + 86400;
    let description: felt252 = 600;
    
    start_cheat_block_timestamp(contract_address, current_time);
    start_cheat_caller_address(contract_address, owner);
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    dispatcher.deposit(goal_id, 1000);
    stop_cheat_caller_address(contract_address);
    
    // Goal should be automatically completed when target is reached
    let (_, _, _, _, _, _, completed) = dispatcher.get_goal_info(goal_id);
    assert(completed == true, 0);
    
    stop_cheat_block_timestamp(contract_address);
}

#[test]
#[should_panic]
fn test_withdraw_from_completed_goal_should_fail() {
    let owner: ContractAddress = 7.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let goal_id: felt252 = 7;
    let target_amount: u256 = 1000;
    let current_time: u64 = 7000000;
    let deadline: u64 = current_time + 86400;
    let description: felt252 = 700;
    
    start_cheat_block_timestamp(contract_address, current_time);
    start_cheat_caller_address(contract_address, owner);
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    dispatcher.deposit(goal_id, 1000);
    stop_cheat_caller_address(contract_address);
    
    // This should fail - cannot withdraw from completed goal
    start_cheat_caller_address(contract_address, owner);
    dispatcher.withdraw(goal_id, 100);
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}

#[test]
fn test_penalty_and_bonus() {
    let owner: ContractAddress = 8.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let goal_id: felt252 = 8;
    let target_amount: u256 = 1000;
    let current_time: u64 = 8000000;
    let deadline: u64 = current_time + 86400;
    let description: felt252 = 800;
    
    start_cheat_block_timestamp(contract_address, current_time);
    start_cheat_caller_address(contract_address, owner);
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    
    // Apply penalty
    dispatcher.apply_penalty(goal_id, 50);
    let penalty = dispatcher.get_penalties(goal_id);
    assert(penalty == 50, 0);
    
    // Apply bonus
    dispatcher.apply_bonus(goal_id, 30);
    let bonus = dispatcher.get_bonuses(goal_id);
    assert(bonus == 30, 0);
    
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}

#[test]
#[should_panic]
fn test_create_goal_with_past_deadline_should_fail() {
    let owner: ContractAddress = 9.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let goal_id: felt252 = 9;
    let target_amount: u256 = 1000;
    let current_time: u64 = 9000000;
    let deadline: u64 = current_time - 1; // Past deadline
    let description: felt252 = 900;
    
    start_cheat_block_timestamp(contract_address, current_time);
    // This should fail - deadline must be in the future
    start_cheat_caller_address(contract_address, owner);
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
}

#[test]
fn test_get_user_goals() {
    let owner: ContractAddress = 10.try_into().unwrap();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    
    let current_time: u64 = 10000000;
    let deadline: u64 = current_time + 86400;
    
    start_cheat_block_timestamp(contract_address, current_time);
    start_cheat_caller_address(contract_address, owner);
    
    dispatcher.create_savings_goal(10, 1000, deadline, 100);
    dispatcher.create_savings_goal(11, 2000, deadline, 200);
    dispatcher.create_savings_goal(12, 3000, deadline, 300);
    
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
    
    let goal_count = dispatcher.get_goal_count(owner.into());
    assert(goal_count == 3, 0);
    
    let goals = dispatcher.get_user_goals(owner.into());
    assert(goals.len() == 3, 0);
}
