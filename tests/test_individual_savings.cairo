use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use core::array::ArrayTrait;
use starknetjello::IIndividualSavingsDispatcher;
use starknetjello::IIndividualSavingsDispatcherTrait;
use starknet::contract_address_const;

fn deploy_individual_savings(owner: ContractAddress) -> ContractAddress {
    let contract = declare("individualsavings").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    constructor_calldata.append(owner.into());
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

#[test]
#[should_panic]
fn test_deposit_zero_should_fail() {
    let owner = contract_address_const::<0>();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    let goal_id: felt252 = 4;
    let target_amount: u256 = 1000;
    let deadline: u64 = 9999999999;
    let description: felt252 = 1;
    // No simulamos el caller, pero el test sirve para ver el assert de amount
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    // Esto debe fallar
    dispatcher.deposit(goal_id, 0);
}

#[test]
#[should_panic]
fn test_withdraw_too_much_should_fail() {
    let owner = contract_address_const::<0>();
    let contract_address = deploy_individual_savings(owner);
    let dispatcher = IIndividualSavingsDispatcher { contract_address };
    let goal_id: felt252 = 5;
    let target_amount: u256 = 1000;
    let deadline: u64 = 9999999999;
    let description: felt252 = 2;
    dispatcher.create_savings_goal(goal_id, target_amount, deadline, description);
    dispatcher.deposit(goal_id, 100);
    // Esto debe fallar
    dispatcher.withdraw(goal_id, 200);
} 