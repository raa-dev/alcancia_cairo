// SPDX-License-Identifier: MIT
// Mock ERC20 Token for Testing

use starknet::ContractAddress;
use core::integer::u256;

#[starknet::interface]
pub trait IMockERC20<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
}

#[starknet::contract]
pub mod mockerc20 {
    use super::IMockERC20;
    use starknet::ContractAddress;
    use starknet::storage::Map;
    use starknet::storage::{StorageMapWriteAccess, StorageMapReadAccess};
    use core::integer::u256;

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        // Initialize with zero balances
    }

    #[abi(embed_v0)]
    impl MockERC20Impl of IMockERC20<ContractState> {
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = starknet::get_caller_address();
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 1); // Insufficient balance
            self.balances.write(sender, sender_balance - amount);
            let recipient_balance = self.balances.read(recipient);
            self.balances.write(recipient, recipient_balance + amount);
            true
        }

        fn transfer_from(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let spender = starknet::get_caller_address();
            let allowance = self.allowances.read((sender, spender));
            assert(allowance >= amount, 2); // Insufficient allowance
            self.allowances.write((sender, spender), allowance - amount);
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 3); // Insufficient balance
            self.balances.write(sender, sender_balance - amount);
            let recipient_balance = self.balances.read(recipient);
            self.balances.write(recipient, recipient_balance + amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let owner = starknet::get_caller_address();
            self.allowances.write((owner, spender), amount);
            true
        }

        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self.allowances.read((owner, spender))
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            let balance = self.balances.read(to);
            self.balances.write(to, balance + amount);
        }
    }
}

