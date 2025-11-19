use starknet::ContractAddress;

// AssetConfig struct matching the pool contract
#[derive(PartialEq, Copy, Drop, Serde)]
pub struct AssetConfig {
    pub total_collateral_shares: u256,
    pub total_nominal_debt: u256,
    pub reserve: u256,
    pub max_utilization: u256,
    pub floor: u256,
    pub scale: u256,
    pub is_legacy: bool,
    pub last_updated: u64,
    pub last_rate_accumulator: u256,
    pub last_full_utilization_rate: u256,
    pub fee_rate: u256,
    pub fee_shares: u256,
}

#[starknet::interface]
pub trait IPool<TContractState> {
    fn utilization(self: @TContractState, asset: ContractAddress) -> u256;
    fn asset_config(self: @TContractState, asset: ContractAddress) -> AssetConfig;
    fn interest_rate(
        self: @TContractState,
        asset: ContractAddress,
        utilization: u256,
        last_updated: u64,
        last_full_utilization_rate: u256,
    ) -> u256;
}

