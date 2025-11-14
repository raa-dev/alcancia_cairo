use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address, stop_cheat_caller_address};
use alcancia::IGroupSavingsDispatcher;
use alcancia::IGroupSavingsDispatcherTrait;
use alcancia::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};
use core::array::ArrayTrait;
use core::traits::TryInto;

fn deploy_contract() -> ContractAddress {
    let contract = declare("groupsavings").unwrap().contract_class();
    let admin: ContractAddress = 999.try_into().unwrap();
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

fn setup_token_and_contract() -> (ContractAddress, ContractAddress) {
    let contract_address = deploy_contract();
    let token_address = deploy_mock_token();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    
    // Set token address as admin
    let admin: ContractAddress = 999.try_into().unwrap();
    start_cheat_caller_address(contract_address, admin);
    dispatcher.set_token_address(token_address);
    stop_cheat_caller_address(contract_address);
    
    (contract_address, token_address)
}

#[test]
fn test_register_group_and_save() {
    let (contract_address, token_address) = setup_token_and_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };

    // Register group: id=1, name=100, members=[10, 20]
    dispatcher.register_group(1, 100, array![10, 20]);

    // Verify group was registered
    let size = dispatcher.get_group_size(1);
    assert(size == 2, 0);
    
    let member0 = dispatcher.get_group_member(1, 0);
    let member1 = dispatcher.get_group_member(1, 1);
    assert(member0 == 10, 0);
    assert(member1 == 20, 0);

    // Mint tokens to members and approve contract
    let caller_10: ContractAddress = 10.try_into().unwrap();
    let caller_20: ContractAddress = 20.try_into().unwrap();
    token.mint(caller_10, 1000);
    token.mint(caller_20, 1000);
    start_cheat_caller_address(token_address, caller_10);
    token.approve(contract_address, 1000);
    stop_cheat_caller_address(token_address);
    start_cheat_caller_address(token_address, caller_20);
    token.approve(contract_address, 1000);
    stop_cheat_caller_address(token_address);

    // Member 10 saves
    start_cheat_caller_address(contract_address, caller_10);
    dispatcher.save(1, 10, 50);
    stop_cheat_caller_address(contract_address);

    // Member 20 saves
    start_cheat_caller_address(contract_address, caller_20);
    dispatcher.save(1, 20, 30);
    stop_cheat_caller_address(contract_address);

    let total = dispatcher.get_group_total(1);
    assert(total == 80, 0);

    let savings_10 = dispatcher.get_member_savings(1, 10);
    let savings_20 = dispatcher.get_member_savings(1, 20);
    assert(savings_10 == 50, 0);
    assert(savings_20 == 30, 0);

    // Verify token balances
    assert(token.balance_of(contract_address) == 80, 0);
    assert(token.balance_of(caller_10) == 950, 0);
    assert(token.balance_of(caller_20) == 970, 0);
}

#[test]
#[should_panic]
fn test_save_zero_should_fail() {
    let (contract_address, _) = setup_token_and_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    dispatcher.register_group(2, 200, array![30]);
    
    let caller_30: ContractAddress = 30.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller_30);
    // This should fail - amount cannot be zero
    dispatcher.save(2, 30, 0);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic]
fn test_save_unauthorized_member_should_fail() {
    let (contract_address, _) = setup_token_and_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    dispatcher.register_group(3, 300, array![40]);
    
    // Try to save as member 50 (not in group) for member 40
    let caller_50: ContractAddress = 50.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller_50);
    // This should fail - caller must be the member
    dispatcher.save(3, 40, 100);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic]
fn test_save_for_nonexistent_group_should_fail() {
    let (contract_address, _) = setup_token_and_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    
    let caller_10: ContractAddress = 10.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller_10);
    // This should fail - group doesn't exist
    dispatcher.save(999, 10, 100);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic]
fn test_register_duplicate_group_should_fail() {
    let (contract_address, _) = setup_token_and_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    
    dispatcher.register_group(4, 400, array![60]);
    // This should fail - group already exists
    dispatcher.register_group(4, 500, array![70]);
}

#[test]
#[should_panic]
fn test_register_group_with_duplicate_members_should_fail() {
    let (contract_address, _) = setup_token_and_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    
    // This should fail - duplicate members
    dispatcher.register_group(5, 500, array![80, 80]);
}

#[test]
fn test_is_group_member() {
    let (contract_address, _) = setup_token_and_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    
    dispatcher.register_group(6, 600, array![90, 91, 92]);
    
    let is_member_90 = dispatcher.is_group_member(6, 90);
    let is_member_91 = dispatcher.is_group_member(6, 91);
    let is_member_99 = dispatcher.is_group_member(6, 99);
    
    assert(is_member_90 == true, 0);
    assert(is_member_91 == true, 0);
    assert(is_member_99 == false, 0);
}

#[test]
#[should_panic]
fn test_get_group_member_out_of_bounds_should_fail() {
    let (contract_address, _) = setup_token_and_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    
    dispatcher.register_group(7, 700, array![100]);
    // This should fail - index out of bounds
    dispatcher.get_group_member(7, 5);
}

#[test]
fn test_withdraw() {
    let (contract_address, token_address) = setup_token_and_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    let token = IMockERC20Dispatcher { contract_address: token_address };

    // Register group
    dispatcher.register_group(8, 800, array![110]);

    // Setup: mint tokens, approve, and deposit
    let caller_110: ContractAddress = 110.try_into().unwrap();
    token.mint(caller_110, 1000);
    start_cheat_caller_address(token_address, caller_110);
    token.approve(contract_address, 1000);
    stop_cheat_caller_address(token_address);
    
    start_cheat_caller_address(contract_address, caller_110);
    dispatcher.save(8, 110, 500);
    stop_cheat_caller_address(contract_address);

    // Verify initial state
    assert(dispatcher.get_member_savings(8, 110) == 500, 0);
    assert(token.balance_of(contract_address) == 500, 0);

    // Withdraw
    start_cheat_caller_address(contract_address, caller_110);
    dispatcher.withdraw(8, 110, 200);
    stop_cheat_caller_address(contract_address);

    // Verify withdrawal
    assert(dispatcher.get_member_savings(8, 110) == 300, 0);
    assert(dispatcher.get_group_total(8) == 300, 0);
    assert(token.balance_of(contract_address) == 300, 0);
    assert(token.balance_of(caller_110) == 700, 0);
}
