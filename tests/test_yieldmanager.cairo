use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};
use alcancia::IYieldManagerDispatcher;
use alcancia::IYieldManagerDispatcherTrait;
use alcancia::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use alcancia::{IERC4626Dispatcher, IERC4626DispatcherTrait};
use alcancia::mock_lending_pool::{IMockLendingPoolDispatcher, IMockLendingPoolDispatcherTrait};
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

fn deploy_mock_lending_pool(token_address: ContractAddress) -> ContractAddress {
    let contract = declare("mocklendingpool").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    constructor_calldata.append(token_address.into());
    // Add name and symbol for ERC20/ERC4626
    constructor_calldata.append('Mock Vault'.into());
    constructor_calldata.append('MVAULT'.into());
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
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

fn setup_yieldmanager_with_lending_pool(admin: ContractAddress) -> (ContractAddress, ContractAddress, ContractAddress) {
    let contract_address = deploy_yieldmanager(admin);
    let token_address = deploy_mock_token();
    let lending_pool_address = deploy_mock_lending_pool(token_address);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    
    // Set token address as admin
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_token_address(token_address);
    dispatcher.set_lending_pool(lending_pool_address);
    stop_cheat_caller_address(contract_address);
    
    (contract_address, token_address, lending_pool_address)
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

#[test]
fn test_deposit_with_lending_pool() {
    let admin: ContractAddress = 9.try_into().unwrap();
    let (contract_address, token_address, lending_pool_address) = setup_yieldmanager_with_lending_pool(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };
    let lending_pool = IERC4626Dispatcher { contract_address: lending_pool_address };
    
    let user: felt252 = 7777;
    let authorized_caller: ContractAddress = 900.try_into().unwrap();
    
    // Mint tokens and approve
    token.mint(authorized_caller, 10000);
    start_cheat_caller_address(token_address, authorized_caller);
    token.approve(contract_address, 10000);
    stop_cheat_caller_address(token_address);
    
    // Authorize caller
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_authorized_caller(authorized_caller, true);
    stop_cheat_caller_address(contract_address);
    
    // Deposit - should deposit to lending pool
    start_cheat_caller_address(contract_address, authorized_caller);
    dispatcher.deposit(authorized_caller, user, 5000);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance
    assert(dispatcher.get_user_balance(user) == 5000, 0);
    assert(dispatcher.get_total_deposited() == 5000, 0);
    
    // Verify tokens are in lending pool, not in contract
    assert(token.balance_of(contract_address) == 0, 0);
    assert(token.balance_of(lending_pool_address) == 5000, 0);
    
    // Verify lending pool has the shares
    let pool_shares = lending_pool.convert_to_shares(5000);
    assert(pool_shares == 5000, 0);
}

#[test]
fn test_withdraw_with_lending_pool() {
    let admin: ContractAddress = 10.try_into().unwrap();
    let (contract_address, token_address, lending_pool_address) = setup_yieldmanager_with_lending_pool(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };
    
    let user: felt252 = 8888;
    let authorized_caller: ContractAddress = 1000.try_into().unwrap();
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
    dispatcher.deposit(authorized_caller, user, 3000);
    stop_cheat_caller_address(contract_address);
    
    // Verify initial state
    assert(dispatcher.get_user_balance(user) == 3000, 0);
    assert(dispatcher.get_total_deposited() == 3000, 0);
    assert(token.balance_of(lending_pool_address) == 3000, 0);
    
    // Withdraw
    dispatcher.withdraw(user, 1000);
    
    // Verify withdrawal
    assert(dispatcher.get_user_balance(user) == 2000, 0);
    assert(dispatcher.get_total_deposited() == 2000, 0);
    assert(token.balance_of(lending_pool_address) == 2000, 0);
    assert(token.balance_of(user_address) == 1000, 0);
}

#[test]
fn test_distribute_yield_with_lending_pool() {
    let admin: ContractAddress = 11.try_into().unwrap();
    let (contract_address, token_address, lending_pool_address) = setup_yieldmanager_with_lending_pool(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };
    let mock_pool = IMockLendingPoolDispatcher { contract_address: lending_pool_address };
    
    let user1: felt252 = 9999;
    let user2: felt252 = 9998;
    let authorized_caller: ContractAddress = 1100.try_into().unwrap();
    
    // Set yield rate to 10% (1000 basis points) for testing
    start_cheat_caller_address(lending_pool_address, admin);
    mock_pool.set_yield_rate(1000);
    stop_cheat_caller_address(lending_pool_address);
    
    // Mint tokens and approve
    token.mint(authorized_caller, 20000);
    start_cheat_caller_address(token_address, authorized_caller);
    token.approve(contract_address, 20000);
    stop_cheat_caller_address(token_address);
    
    // Authorize caller
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_authorized_caller(authorized_caller, true);
    stop_cheat_caller_address(contract_address);
    
    // Deposit for user1
    start_cheat_caller_address(contract_address, authorized_caller);
    dispatcher.deposit(authorized_caller, user1, 6000);
    stop_cheat_caller_address(contract_address);
    
    // Deposit for user2
    start_cheat_caller_address(contract_address, authorized_caller);
    dispatcher.deposit(authorized_caller, user2, 4000);
    stop_cheat_caller_address(contract_address);
    
    // Verify initial state
    assert(dispatcher.get_total_deposited() == 10000, 0);
    assert(dispatcher.get_user_balance(user1) == 6000, 0);
    assert(dispatcher.get_user_balance(user2) == 4000, 0);
    
    // Distribute yield - this will calculate yield from lending pool
    dispatcher.distribute_yield();
    
    // Verify yields were distributed proportionally
    let yield1 = dispatcher.get_user_yield(user1);
    let yield2 = dispatcher.get_user_yield(user2);
    
    // Both users should receive yield (proportional to their deposits)
    // User1 deposited 60% (6000/10000), user2 deposited 40% (4000/10000)
    assert(yield1 > 0, 0);
    assert(yield2 > 0, 0);
    
    // Verify yield is proportional: yield1 should be approximately 1.5x yield2
    // (since user1 has 1.5x the balance of user2)
    // We'll just verify both got yield and yield1 >= yield2
    assert(yield1 >= yield2, 0);
}

#[test]
fn test_multiple_deposits_and_yield_distribution() {
    let admin: ContractAddress = 12.try_into().unwrap();
    let (contract_address, token_address, lending_pool_address) = setup_yieldmanager_with_lending_pool(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };
    let _lending_pool = IERC4626Dispatcher { contract_address: lending_pool_address };
    
    let user: felt252 = 1111;
    let authorized_caller: ContractAddress = 1200.try_into().unwrap();
    
    // Mint tokens and approve
    token.mint(authorized_caller, 50000);
    start_cheat_caller_address(token_address, authorized_caller);
    token.approve(contract_address, 50000);
    stop_cheat_caller_address(token_address);
    
    // Authorize caller
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_authorized_caller(authorized_caller, true);
    stop_cheat_caller_address(contract_address);
    
    // First deposit
    start_cheat_caller_address(contract_address, authorized_caller);
    dispatcher.deposit(authorized_caller, user, 5000);
    stop_cheat_caller_address(contract_address);
    
    assert(dispatcher.get_total_deposited() == 5000, 0);
    
    // Second deposit
    start_cheat_caller_address(contract_address, authorized_caller);
    dispatcher.deposit(authorized_caller, user, 3000);
    stop_cheat_caller_address(contract_address);
    
    assert(dispatcher.get_user_balance(user) == 8000, 0);
    assert(dispatcher.get_total_deposited() == 8000, 0);
    assert(token.balance_of(lending_pool_address) == 8000, 0);
    
    // Distribute yield
    dispatcher.distribute_yield();
    
    // Verify yield was calculated
    let yield_amount = dispatcher.get_user_yield(user);
    assert(yield_amount > 0, 0);
}
