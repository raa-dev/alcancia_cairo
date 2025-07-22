use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use starknetjello::IYieldManagerDispatcher;
use starknetjello::IYieldManagerDispatcherTrait;
use starknet::contract_address_const;

fn deploy_yieldmanager(admin: ContractAddress) -> ContractAddress {
    let contract = declare("yieldmanager").unwrap().contract_class();
    let mut constructor_calldata = ArrayTrait::new();
    constructor_calldata.append(admin.into());
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    contract_address
}

#[test]
fn test_deposit_and_yield() {
    let admin = contract_address_const::<0>();
    let contract_address = deploy_yieldmanager(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let user: felt252 = 1234;
    let caller = contract_address_const::<0>(); // Simula GroupSavings autorizado
    dispatcher.set_admin_for_test(admin);
    // Autorizar caller
    dispatcher.set_authorized_caller(caller, true);
    // Depositar
    dispatcher.deposit(caller, user, 1000);
    // Verificar balance
    let bal = dispatcher.get_user_balance(user);
    assert(bal == 1000, 0);
    // Distribuir yield (5%)
    dispatcher.distribute_yield();
    // Verificar yield
    let y = dispatcher.get_user_yield(user);
    assert(y == 50, 0); // 5% de 1000
}

#[test]
fn test_penalty_and_bonus() {
    let admin = contract_address_const::<0>();
    let contract_address = deploy_yieldmanager(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let user: felt252 = 2222;
    let caller = contract_address_const::<0>();
    dispatcher.set_admin_for_test(admin);
    dispatcher.deposit(caller, user, 2000);
    // Asignar penalización y bono
    dispatcher.set_penalty(user, 50);
    dispatcher.set_bonus(user, 30);
    dispatcher.distribute_yield();
    // Verificar yield
    let y = dispatcher.get_user_yield(user);
    // 5% de 2000 = 100, +30 bono -50 penalización = 80
    assert(y == 80, 0);
}

#[test]
fn test_update_strategy() {
    let admin = contract_address_const::<0>();
    let contract_address = deploy_yieldmanager(admin);
    let dispatcher = IYieldManagerDispatcher { contract_address };
    let new_strategy = contract_address_const::<99>();
    dispatcher.set_admin_for_test(admin);
    dispatcher.update_strategy(new_strategy);
    let strategy = dispatcher.get_strategy();
    assert(strategy == new_strategy, 0);
} 