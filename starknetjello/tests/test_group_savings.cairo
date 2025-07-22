use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use starknetjello::IGroupSavingsDispatcher;
use starknetjello::IGroupSavingsDispatcherTrait;

fn deploy_contract() -> ContractAddress {
    let contract = declare("groupsavings").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

#[test]
fn test_register_group_and_save() {
    let contract_address = deploy_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };

    // Grupo: id=1, nombre=[100], miembros=[10, 20]
    dispatcher.register_group(1, 100, array![10, 20]);

    // Ahorro miembro 10
    dispatcher.save(1, 10, 50);
    // Ahorro miembro 20
    dispatcher.save(1, 20, 30);

    let total = dispatcher.get_group_total(1);
    assert(total == 80, 80);

    let savings_10 = dispatcher.get_member_savings(1, 10);
    let savings_20 = dispatcher.get_member_savings(1, 20);
    assert(savings_10 == 50, 50);
    assert(savings_20 == 30, 30);
}

#[test]
#[should_panic]
fn test_save_zero_should_fail() {
    let contract_address = deploy_contract();
    let dispatcher = IGroupSavingsDispatcher { contract_address };
    dispatcher.register_group(2, 200, array![30]);
    // Esto debe fallar
    dispatcher.save(2, 30, 0);
} 