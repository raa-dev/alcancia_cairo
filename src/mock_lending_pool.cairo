// SPDX-License-Identifier: MIT
// Mock Lending Pool (ERC4626) for Testing

use core::integer::u256;

// Import IERC4626 interface from lib.cairo (custom ERC4626 interface)
use alcancia::IERC20Dispatcher;
use alcancia::IERC20DispatcherTrait;

// Additional interface for testing utilities
#[starknet::interface]
pub trait IMockLendingPool<TContractState> {
    fn set_yield_rate(ref self: TContractState, rate: u256); // For testing: set yield rate
}

#[starknet::contract]
pub mod mocklendingpool {
    use alcancia::IERC4626;
    use super::{IERC20Dispatcher, IERC20DispatcherTrait, IMockLendingPool};
    use starknet::ContractAddress;
    use starknet::storage::Map;
    use starknet::storage::{StorageMapWriteAccess, StorageMapReadAccess};
    use core::integer::u256;

    #[storage]
    struct Storage {
        asset_address: Map<(), ContractAddress>,
        base_assets: Map<(), u256>, // Base assets deposited (renamed to avoid conflict with total_assets function)
        total_supply: Map<(), u256>, // Total shares
        shares: Map<ContractAddress, u256>, // User shares
        yield_rate: Map<(), u256>, // Annual yield rate in basis points (e.g., 500 = 5%)
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        asset_address: ContractAddress,
        _name: felt252,
        _symbol: felt252
    ) {
        self.asset_address.write((), asset_address);
        self.base_assets.write((), 0);
        self.total_supply.write((), 0);
        self.yield_rate.write((), 500); // Default 5% annual yield
    }

    #[abi(embed_v0)]
    impl MockLendingPoolImpl of alcancia::IERC4626<ContractState> {
        fn asset(self: @ContractState) -> ContractAddress {
            self.asset_address.read(())
        }

        fn total_assets(self: @ContractState) -> u256 {
            // Simulate yield accumulation
            let base_assets = self.base_assets.read(());
            let yield_rate = self.yield_rate.read(());
            
            // Simple yield calculation: add small amount per call (simulating time passage)
            // In real scenario, this would be based on actual time and rate
            // For testing, we'll just return base + a small yield
            let yield_amount = base_assets * yield_rate / 10000; // Convert basis points to percentage
            base_assets + yield_amount
        }

        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            let total_assets_value = self.total_assets();
            let total_supply_value = self.total_supply.read(());
            
            // ERC4626: shares = assets * totalSupply / totalAssets (if totalSupply > 0)
            if total_supply_value == 0 {
                assets // First deposit: 1:1
            } else if total_assets_value == 0 {
                0
            } else {
                (assets * total_supply_value) / total_assets_value
            }
        }

        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            let total_assets_value = self.total_assets();
            let total_supply_value = self.total_supply.read(());
            
            // ERC4626: assets = shares * totalAssets / totalSupply
            if total_supply_value == 0 {
                0
            } else {
                (shares * total_assets_value) / total_supply_value
            }
        }

        fn max_deposit(self: @ContractState, receiver: ContractAddress) -> u256 {
            // No limits in mock - return max u256
            let _ = receiver; // Suppress unused parameter warning
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256
        }

        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            // Preview should match convert_to_shares (no fees in mock)
            self.convert_to_shares(assets)
        }

        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            let asset_address = self.asset_address.read(());
            let token = IERC20Dispatcher { contract_address: asset_address };
            let self_address = starknet::get_contract_address();
            let caller = starknet::get_caller_address();
            
            // Transfer tokens from caller to vault
            // The caller (YieldManager) has already approved this contract
            token.transfer_from(caller, self_address, assets);
            
            // Calculate shares using ERC4626 formula
            let shares = self.convert_to_shares(assets);
            
            // Update state
            let base_assets = self.base_assets.read(());
            self.base_assets.write((), base_assets + assets);
            
            let user_shares = self.shares.read(receiver);
            self.shares.write(receiver, user_shares + shares);
            
            let total_supply = self.total_supply.read(());
            self.total_supply.write((), total_supply + shares);
            
            shares
        }

        fn max_mint(self: @ContractState, receiver: ContractAddress) -> u256 {
            // No limits in mock - return max u256
            let _ = receiver; // Suppress unused parameter warning
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF_u256
        }

        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            // Preview should match convert_to_assets (no fees in mock)
            self.convert_to_assets(shares)
        }

        fn mint(ref self: ContractState, shares: u256, receiver: ContractAddress) -> u256 {
            // Calculate assets needed
            let assets = self.convert_to_assets(shares);
            
            // Use deposit logic
            let _deposited_shares = self.deposit(assets, receiver);
            assets
        }

        fn max_withdraw(self: @ContractState, owner: ContractAddress) -> u256 {
            // Can withdraw up to their share value
            let owner_shares = self.shares.read(owner);
            self.convert_to_assets(owner_shares)
        }

        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            // Preview shares needed
            self.convert_to_shares(assets)
        }

        fn withdraw(
            ref self: ContractState,
            assets: u256,
            receiver: ContractAddress,
            owner: ContractAddress
        ) -> u256 {
            let asset_address = self.asset_address.read(());
            let token = IERC20Dispatcher { contract_address: asset_address };
            
            // Calculate shares needed
            let shares = self.convert_to_shares(assets);
            
            // Check balance
            let owner_shares = self.shares.read(owner);
            assert(owner_shares >= shares, 1); // Insufficient shares
            
            // Update state
            let base_assets = self.base_assets.read(());
            assert(base_assets >= assets, 2); // Insufficient assets in pool
            
            self.base_assets.write((), base_assets - assets);
            self.shares.write(owner, owner_shares - shares);
            
            let total_supply = self.total_supply.read(());
            self.total_supply.write((), total_supply - shares);
            
            // Transfer tokens to receiver
            token.transfer(receiver, assets);
            
            shares
        }

        fn max_redeem(self: @ContractState, owner: ContractAddress) -> u256 {
            // Can redeem all their shares
            self.shares.read(owner)
        }

        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            // Preview assets received
            self.convert_to_assets(shares)
        }

        fn redeem(
            ref self: ContractState,
            shares: u256,
            receiver: ContractAddress,
            owner: ContractAddress
        ) -> u256 {
            // Calculate assets to withdraw
            let assets = self.convert_to_assets(shares);
            
            // Use withdraw logic
            let _withdrawn_shares = self.withdraw(assets, receiver, owner);
            assets
        }
    }

    #[abi(embed_v0)]
    impl MockLendingPoolTestImpl of IMockLendingPool<ContractState> {
        fn set_yield_rate(ref self: ContractState, rate: u256) {
            // For testing: allow setting yield rate
            self.yield_rate.write((), rate);
        }
    }
}
