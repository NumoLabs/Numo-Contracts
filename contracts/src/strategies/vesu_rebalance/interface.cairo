use starknet::{ContractAddress};
use numo_contracts::interfaces::IDistributor::{Claim};
use numo_contracts::components::swap::{AvnuMultiRouteSwap};

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub enum Feature {
    #[default]
    DEPOSIT,
    WITHDRAW
}

#[derive(PartialEq, Drop, Copy, Serde)]
pub struct Action {
    pub pool_id: ContractAddress,
    pub feature: Feature,
    // should be asset() when borrowing not enabled
    pub token: ContractAddress,
    pub amount: u256
}

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct PoolProps {
    pub pool_id: ContractAddress, // vesu pool id
    pub max_weight: u32, // in bps relative to total_assets
    pub v_token: ContractAddress,
}

#[derive(Drop, Copy, Serde, starknet::Store)]
// vault general settings
pub struct Settings {
    pub default_pool_index: u8,
    pub fee_bps: u32,
    pub fee_receiver: ContractAddress,
}

#[starknet::interface]
pub trait IVesuRebal<TContractState> {
    fn rebalance(ref self: TContractState, actions: Array<Action>);
    fn rebalance_weights(ref self: TContractState, actions: Array<Action>);
    fn emergency_withdraw(ref self: TContractState);
    fn emergency_withdraw_pool(ref self: TContractState, pool_index: u32);
    fn compute_yield(self: @TContractState) -> (u256, u256);
    fn harvest(
        ref self: TContractState,
        rewardsContract: ContractAddress,
        claim: Claim,
        proof: Span<felt252>,
        swapInfo: AvnuMultiRouteSwap
    );

    // setters
    fn set_settings(ref self: TContractState, settings: Settings);
    fn set_allowed_pools(ref self: TContractState, pools: Array<PoolProps>);
    fn set_incentives_off(ref self: TContractState);

    // getters
    fn get_settings(self: @TContractState) -> Settings;
    fn get_allowed_pools(self: @TContractState) -> Array<PoolProps>;
    fn get_previous_index(self: @TContractState) -> u128;
}


#[starknet::interface]
pub trait IVesuTokenV2<TContractState> {
    fn migrate_v_token(ref self: TContractState,);
    fn v_token_v1(self: @TContractState) -> ContractAddress;
}

#[starknet::interface]
pub trait IVesuMigrate<TContractState> {
    /// @notice Migrates vault to Vesu V2 pool tokens
    /// @dev In V2, new_singleton parameter is unused but kept for interface compatibility
    /// @param new_singleton Unused in V2, kept for interface compatibility
    /// @param new_pool_tokens Array of new V2 pool token addresses to migrate to
    fn vesu_migrate(
        ref self: TContractState,
        new_singleton: ContractAddress, // Unused in V2
        new_pool_tokens: Array<ContractAddress>,
    );
}
