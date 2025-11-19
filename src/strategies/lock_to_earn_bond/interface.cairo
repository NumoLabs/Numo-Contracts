use starknet::{ContractAddress};
use numo_contracts::strategies::vesu_rebalance::interface::{Action, PoolProps, Settings};
use numo_contracts::interfaces::IDistributor::{Claim};
use numo_contracts::components::swap::{AvnuMultiRouteSwap};

#[starknet::interface]
pub trait ILockToEarnBond<TContractState> {
    /// @notice Deposits assets into the vault with a lock period
    /// @dev The assets will be locked for a specific period defined in the lock period setting
    /// @param assets The amount of assets to deposit
    /// @param receiver The address that will receive the vault shares
    /// @return shares The amount of vault shares minted
    fn deposit_locked(
        ref self: TContractState,
        assets: u256,
        receiver: ContractAddress
    ) -> u256;

    /// @notice Deposits assets into the vault with a custom lock period
    /// @dev Allows setting a custom lock period for this specific deposit
    /// @param assets The amount of assets to deposit
    /// @param receiver The address that will receive the vault shares
    /// @param lock_period_seconds The lock period in seconds for this deposit
    /// @return shares The amount of vault shares minted
    fn deposit_with_custom_lock(
        ref self: TContractState,
        assets: u256,
        receiver: ContractAddress,
        lock_period_seconds: u64
    ) -> u256;


    /// @notice Gets the lock information for a specific user
    /// @param user The user address
    /// @return lock_until The timestamp until which the user's funds are locked (0 if not locked)
    /// @return locked_amount The amount of shares that are currently locked
    fn get_lock_info(self: @TContractState, user: ContractAddress) -> (u64, u256);

    /// @notice Checks if a user can withdraw (lock period has passed)
    /// @param user The user address
    /// @return can_withdraw True if the user can withdraw, false otherwise
    fn can_withdraw(self: @TContractState, user: ContractAddress) -> bool;

    // VesuRebalance compatible functions
    fn rebalance(ref self: TContractState, actions: Array<Action>);
    fn rebalance_weights(ref self: TContractState, actions: Array<Action>);
    fn emergency_withdraw(ref self: TContractState, users_to_burn: Array<ContractAddress>);
    fn emergency_withdraw_pool(ref self: TContractState, pool_index: u32);
    fn emergency_withdraw_user(ref self: TContractState, user: ContractAddress);
    fn emergency_transfer_asset(ref self: TContractState, receiver: ContractAddress, amount: u256);
    fn emergency_burn_shares(ref self: TContractState, user: ContractAddress, shares: u256);
    fn compute_yield(self: @TContractState) -> (u256, u256);
    fn harvest(
        ref self: TContractState,
        rewardsContract: ContractAddress,
        claim: Claim,
        proof: Span<felt252>,
        swapInfo: AvnuMultiRouteSwap
    );

    // Setters (governor only)
    fn set_settings(ref self: TContractState, settings: Settings);
    fn set_allowed_pools(ref self: TContractState, pools: Array<PoolProps>);
    fn set_incentives_off(ref self: TContractState);
    fn set_lock_period(ref self: TContractState, lock_period_seconds: u64);
    fn set_min_lock_period(ref self: TContractState, min_lock_period_seconds: u64);
    fn set_max_lock_period(ref self: TContractState, max_lock_period_seconds: u64);

    // Getters
    fn get_settings(self: @TContractState) -> Settings;
    fn get_allowed_pools(self: @TContractState) -> Array<PoolProps>;
    fn get_previous_index(self: @TContractState) -> u128;
    fn get_lock_period(self: @TContractState) -> u64;
    fn get_min_lock_period(self: @TContractState) -> u64;
    fn get_max_lock_period(self: @TContractState) -> u64;
}

