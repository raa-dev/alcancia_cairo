use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};
use alcancia::IYieldManagerDispatcher;
use alcancia::IYieldManagerDispatcherTrait;
use alcancia::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use core::array::ArrayTrait;
use core::traits::TryInto;

fn deploy_yieldmanager(admin: ContractAddress) -> ContractAddress {
    let contract = declare("yieldmanager").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    constructor_calldata.append(admin.into());
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

fn deploy_mock_token() -> ContractAddress {
    let contract = declare("mockerc20").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

fn setup_yieldmanager_with_token(admin: ContractAddress) -> (ContractAddress, ContractAddress) {
    let contract_address = deploy_yieldmanager(admin);
    let token_address = deploy_mock_token();
    let dispatcher = IYieldManagerDispatcher { contract_address };
    
    // Set token address as admin
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_token_address(token_address);
    stop_cheat_caller_address(contract_address);
    
    (contract_address, token_address)
}

#[test]
fn test_deposit_and_yield() {
    let admin: ContractAddress = 1.try_into().unwrap();
    let (contract_address, token_address) = setup_yieldmanager_with_token(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };
    
    let user: felt252 = 1234;
    let authorized_caller: ContractAddress = 100.try_into().unwrap();
    
    // Mint tokens to authorized caller and approve contract
    token.mint(authorized_caller, 10000);
    start_cheat_caller_address(token_address, authorized_caller);
    token.approve(contract_address, 10000);
    stop_cheat_caller_address(token_address);
    
    // Authorize caller as admin
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_authorized_caller(authorized_caller, true);
    stop_cheat_caller_address(contract_address);
    
    // Deposit as authorized caller
    start_cheat_caller_address(contract_address, authorized_caller);
    dispatcher.deposit(authorized_caller, user, 1000);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance
    let bal = dispatcher.get_user_balance(user);
    assert(bal == 1000, 0);
    
    // Verify token was transferred
    assert(token.balance_of(contract_address) == 1000, 0);
    
    // Distribute yield (5%)
    dispatcher.distribute_yield();
    
    // Verify yield
    let y = dispatcher.get_user_yield(user);
    assert(y == 50, 0); // 5% of 1000
}

#[test]
fn test_penalty_and_bonus() {
    let admin: ContractAddress = 2.try_into().unwrap();
    let (contract_address, token_address) = setup_yieldmanager_with_token(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };
    
    let user: felt252 = 2222;
    let authorized_caller: ContractAddress = 200.try_into().unwrap();
    
    // Mint tokens and approve
    token.mint(authorized_caller, 10000);
    start_cheat_caller_address(token_address, authorized_caller);
    token.approve(contract_address, 10000);
    stop_cheat_caller_address(token_address);
    
    // Authorize caller
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_authorized_caller(authorized_caller, true);
    stop_cheat_caller_address(contract_address);
    
    // Deposit
    start_cheat_caller_address(contract_address, authorized_caller);
    dispatcher.deposit(authorized_caller, user, 2000);
    stop_cheat_caller_address(contract_address);
    
    // Set penalty and bonus as admin
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_penalty(user, 50);
    dispatcher.set_bonus(user, 30);
    stop_cheat_caller_address(contract_address);
    
    // Distribute yield
    dispatcher.distribute_yield();
    
    // Verify yield: 5% of 2000 = 100, +30 bonus -50 penalty = 80
    let y = dispatcher.get_user_yield(user);
    assert(y == 80, 0);
}

#[test]
fn test_update_strategy() {
    let admin: ContractAddress = 3.try_into().unwrap();
    let (contract_address, _) = setup_yieldmanager_with_token(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    
    let new_strategy: ContractAddress = 99.try_into().unwrap();
    
    // Update strategy as admin
    start_cheat_caller_address(contract_address, admin);
    dispatcher.update_strategy(new_strategy);
    stop_cheat_caller_address(contract_address);
    
    let strategy = dispatcher.get_strategy();
    assert(strategy == new_strategy, 0);
}

#[test]
#[should_panic]
fn test_update_strategy_unauthorized_should_fail() {
    let admin: ContractAddress = 4.try_into().unwrap();
    let (contract_address, _) = setup_yieldmanager_with_token(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    
    let new_strategy: ContractAddress = 99.try_into().unwrap();
    let unauthorized: ContractAddress = 999.try_into().unwrap();
    
    // Try to update strategy as unauthorized user
    start_cheat_caller_address(contract_address, unauthorized);
    // This should fail - only admin can update strategy
    dispatcher.update_strategy(new_strategy);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic]
fn test_deposit_unauthorized_should_fail() {
    let admin: ContractAddress = 5.try_into().unwrap();
    let (contract_address, _) = setup_yieldmanager_with_token(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    
    let user: felt252 = 3333;
    let unauthorized_caller: ContractAddress = 500.try_into().unwrap();
    
    // Try to deposit as unauthorized caller
    start_cheat_caller_address(contract_address, unauthorized_caller);
    // This should fail - caller is not authorized
    dispatcher.deposit(unauthorized_caller, user, 1000);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic]
fn test_deposit_zero_amount_should_fail() {
    let admin: ContractAddress = 6.try_into().unwrap();
    let (contract_address, _) = setup_yieldmanager_with_token(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    
    let user: felt252 = 4444;
    let authorized_caller: ContractAddress = 600.try_into().unwrap();
    
    // Authorize caller
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_authorized_caller(authorized_caller, true);
    stop_cheat_caller_address(contract_address);
    
    // Try to deposit zero amount
    start_cheat_caller_address(contract_address, authorized_caller);
    // This should fail - amount must be greater than 0
    dispatcher.deposit(authorized_caller, user, 0);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_yield_with_large_penalty() {
    let admin: ContractAddress = 7.try_into().unwrap();
    let (contract_address, token_address) = setup_yieldmanager_with_token(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };
    
    let user: felt252 = 5555;
    let authorized_caller: ContractAddress = 700.try_into().unwrap();
    
    // Mint tokens and approve
    token.mint(authorized_caller, 10000);
    start_cheat_caller_address(token_address, authorized_caller);
    token.approve(contract_address, 10000);
    stop_cheat_caller_address(token_address);
    
    // Authorize caller
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_authorized_caller(authorized_caller, true);
    stop_cheat_caller_address(contract_address);
    
    // Deposit
    start_cheat_caller_address(contract_address, authorized_caller);
    dispatcher.deposit(authorized_caller, user, 1000);
    stop_cheat_caller_address(contract_address);
    
    // Set penalty larger than yield + bonus
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_penalty(user, 200); // Larger than 5% yield (50)
    stop_cheat_caller_address(contract_address);
    
    // Distribute yield - should handle underflow gracefully
    dispatcher.distribute_yield();
    
    // Yield should be 0 (penalty exceeds yield)
    let y = dispatcher.get_user_yield(user);
    assert(y == 0, 0);
}

#[test]
fn test_withdraw() {
    let admin: ContractAddress = 8.try_into().unwrap();
    let (contract_address, token_address) = setup_yieldmanager_with_token(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };
    
    let user: felt252 = 6666;
    let authorized_caller: ContractAddress = 800.try_into().unwrap();
    let user_address: ContractAddress = user.try_into().unwrap();
    
    // Mint tokens and approve
    token.mint(authorized_caller, 10000);
    start_cheat_caller_address(token_address, authorized_caller);
    token.approve(contract_address, 10000);
    stop_cheat_caller_address(token_address);
    
    // Authorize caller
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_authorized_caller(authorized_caller, true);
    stop_cheat_caller_address(contract_address);
    
    // Deposit
    start_cheat_caller_address(contract_address, authorized_caller);
    dispatcher.deposit(authorized_caller, user, 2000);
    stop_cheat_caller_address(contract_address);
    
    // Verify initial state
    assert(dispatcher.get_user_balance(user) == 2000, 0);
    assert(token.balance_of(contract_address) == 2000, 0);
    
    // Withdraw (anyone can call withdraw for a user, but tokens go to user)
    dispatcher.withdraw(user, 500);
    
    // Verify withdrawal
    assert(dispatcher.get_user_balance(user) == 1500, 0);
    assert(token.balance_of(contract_address) == 1500, 0);
    assert(token.balance_of(user_address) == 500, 0);
}
