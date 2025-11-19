#[starknet::contract]
mod LockToEarnBond {
    use starknet::{ContractAddress, get_contract_address, get_block_number, get_block_timestamp};
    use core::traits::TryInto;
    use numo_contracts::helpers::ERC20Helper;
    use numo_contracts::components::common::CommonComp;
    use numo_contracts::interfaces::IPool::{IPoolDispatcher, IPoolDispatcherTrait};
    use numo_contracts::components::harvester::reward_shares::{
        RewardShareComponent, IRewardShare
    };
    use numo_contracts::components::harvester::reward_shares::RewardShareComponent::{
        InternalTrait as RewardShareInternalImpl
    };
    use numo_contracts::components::harvester::harvester_lib::HarvestBeforeHookResult;
    use numo_contracts::interfaces::IERC4626::{
        IERC4626, IERC4626Dispatcher, IERC4626DispatcherTrait
    };
    use openzeppelin::security::pausable::{PausableComponent};
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use openzeppelin::security::reentrancyguard::{ReentrancyGuardComponent};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::{ERC20Component,};
    use openzeppelin::token::erc20::interface::IERC20Mixin;
    use numo_contracts::components::erc4626::{ERC4626Component};
    use alexandria_storage::list::{List, ListTrait};
    use numo_contracts::interfaces::IDistributor::{Claim};
    use numo_contracts::components::swap::{AvnuMultiRouteSwap};
    use numo_contracts::components::harvester::defi_spring_default_style::{
        SNFStyleClaimSettings, ClaimImpl as DefaultClaimImpl
    };
    use numo_contracts::components::harvester::harvester_lib::{
        HarvestConfig, HarvestConfigImpl, HarvestHooksTrait, HarvestEvent
    };
    use numo_contracts::interfaces::oracle::{IPriceOracleDispatcher};
    use core::num::traits::Zero;
    use numo_contracts::strategies::vesu_rebalance::interface::{
        Action, Feature, PoolProps, Settings
    };
    use numo_contracts::strategies::lock_to_earn_bond::interface::ILockToEarnBond;

    component!(path: ERC4626Component, storage: erc4626, event: ERC4626Event);
    component!(path: RewardShareComponent, storage: reward_share, event: RewardShareEvent);
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: ReentrancyGuardComponent, storage: reng, event: ReentrancyGuardEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: CommonComp, storage: common, event: CommonCompEvent);

    #[abi(embed_v0)]
    impl CommonCompImpl = CommonComp::CommonImpl<ContractState>;

    #[abi(embed_v0)]
    impl RewardShareImpl = RewardShareComponent::RewardShareImpl<ContractState>;
    impl RSInternalImpl = RewardShareComponent::InternalImpl<ContractState>;
    impl RSPrivateImpl = RewardShareComponent::PrivateImpl<ContractState>;

    impl CommonInternalImpl = CommonComp::InternalImpl<ContractState>;
    impl ERC4626InternalImpl = ERC4626Component::InternalImpl<ContractState>;
    impl ERC4626MetadataImpl = ERC4626Component::ERC4626MetadataImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    pub mod Errors {
        pub const INVALID_YIELD: felt252 = 'Insufficient yield';
        pub const INVALID_POOL_ID: felt252 = 'Invalid pool id';
        pub const INVALID_BALANCE: felt252 = 'remaining amount should be zero';
        pub const UNUTILIZED_ASSET: felt252 = 'Unutilized asset in vault';
        pub const MAX_WEIGHT_EXCEEDED: felt252 = 'Max weight exceeded';
        pub const INVALID_POOL_LENGTH: felt252 = 'Invalid pool length';
        pub const INVALID_POOL_CONFIG: felt252 = 'Invalid pool config';
        pub const INVALID_ASSET: felt252 = 'Invalid asset';
        pub const INVALID_HARVEST: felt252 = 'Invalid harvest';
        pub const STILL_LOCKED: felt252 = 'Funds are still locked';
        pub const INVALID_LOCK_PERIOD: felt252 = 'Invalid lock period';
        pub const LOCK_PERIOD_EXCEEDED: felt252 = 'Lock period exceeds maximum';
        pub const LOCK_PERIOD_TOO_SHORT: felt252 = 'Lock period below minimum';
    }

    #[derive(Drop, Copy, Serde, starknet::Store)]
    struct LockInfo {
        pub lock_until: u64,  // Timestamp until which funds are locked
        pub locked_shares: u256,  // Amount of shares locked
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        reng: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        reward_share: RewardShareComponent::Storage,
        #[substorage(v0)]
        erc4626: ERC4626Component::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        common: CommonComp::Storage,
        allowed_pools: List<PoolProps>,
        settings: Settings,
        previous_index: u128,
        oracle: ContractAddress,
        is_incentives_on: bool,
        // Lock to earn bond specific storage
        user_locks: starknet::storage::Map<ContractAddress, LockInfo>,
        default_lock_period: u64,  // Default lock period in seconds
        min_lock_period: u64,  // Minimum lock period in seconds
        max_lock_period: u64,  // Maximum lock period in seconds
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        #[flat]
        ERC4626Event: ERC4626Component::Event,
        #[flat]
        RewardShareEvent: RewardShareComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        CommonCompEvent: CommonComp::Event,
        Rebalance: Rebalance,
        CollectFees: CollectFees,
        Harvest: HarvestEvent,
        FundsLocked: FundsLocked,
        FundsUnlocked: FundsUnlocked,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Rebalance {
        yield_before: u128,
        yield_after: u128,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CollectFees {
        fee_collected: u128,
        fee_collector: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FundsLocked {
        user: ContractAddress,
        shares: u256,
        lock_until: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FundsUnlocked {
        user: ContractAddress,
        shares: u256,
    }

    const DEFAULT_INDEX: u128 = 1000_000_000_000_000_000;

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        asset: ContractAddress,
        access_control: ContractAddress,
        allowed_pools: Array<PoolProps>,
        settings: Settings,
        oracle: ContractAddress,
        default_lock_period: u64,
        min_lock_period: u64,
        max_lock_period: u64,
    ) {
        self.erc4626.initializer(asset);
        self.erc20.initializer(name, symbol);
        self.common.initializer(access_control);
        self._set_pool_settings(allowed_pools);

        self.settings.write(settings);
        self.oracle.write(oracle);

        // default index 10**18 (i.e. 1)
        self.previous_index.write(DEFAULT_INDEX);

        // since defi spring is active now
        self.is_incentives_on.write(true);

        self.reward_share.init(get_block_number());

        // Lock to earn bond settings
        assert(min_lock_period <= default_lock_period, Errors::INVALID_LOCK_PERIOD);
        assert(default_lock_period <= max_lock_period, Errors::INVALID_LOCK_PERIOD);
        self.default_lock_period.write(default_lock_period);
        self.min_lock_period.write(min_lock_period);
        self.max_lock_period.write(max_lock_period);
    }

    #[abi(embed_v0)]
    impl LockToEarnBondImpl of ILockToEarnBond<ContractState> {
        /// @notice Deposits assets into the vault with the default lock period
        fn deposit_locked(
            ref self: ContractState,
            assets: u256,
            receiver: ContractAddress
        ) -> u256 {
            let lock_period = self.default_lock_period.read();
            self.deposit_with_custom_lock(assets, receiver, lock_period)
        }

        /// @notice Deposits assets into the vault with a custom lock period
        fn deposit_with_custom_lock(
            ref self: ContractState,
            assets: u256,
            receiver: ContractAddress,
            lock_period_seconds: u64
        ) -> u256 {
            self.common.assert_not_paused();

            // Validate lock period
            let min_lock = self.min_lock_period.read();
            let max_lock = self.max_lock_period.read();
            assert(lock_period_seconds >= min_lock, Errors::LOCK_PERIOD_TOO_SHORT);
            assert(lock_period_seconds <= max_lock, Errors::LOCK_PERIOD_EXCEEDED);

            // Perform the deposit
            let shares = self.erc4626.deposit(assets, receiver);

            // Update lock info
            let current_timestamp = get_block_timestamp();
            let lock_until = current_timestamp + lock_period_seconds;
            
            let lock_info = self.user_locks.read(receiver);
            let mut new_lock_info = lock_info;
            
            if lock_info.lock_until == 0 {
                // New lock
                new_lock_info = LockInfo {
                    lock_until: lock_until,
                    locked_shares: shares
                };
            } else {
                // Existing lock - extend if new lock is longer, and add shares
                let new_lock_until = if lock_until > lock_info.lock_until {
                    lock_until
                } else {
                    lock_info.lock_until
                };
                new_lock_info = LockInfo {
                    lock_until: new_lock_until,
                    locked_shares: lock_info.locked_shares + shares
                };
            }

            self.user_locks.write(receiver, new_lock_info);

            self.emit(FundsLocked {
                user: receiver,
                shares: shares,
                lock_until: lock_until
            });

            shares
        }


        /// @notice Gets lock information for a user
        fn get_lock_info(self: @ContractState, user: ContractAddress) -> (u64, u256) {
            let lock_info = self.user_locks.read(user);
            (lock_info.lock_until, lock_info.locked_shares)
        }

        /// @notice Checks if a user can withdraw
        fn can_withdraw(self: @ContractState, user: ContractAddress) -> bool {
            let lock_info = self.user_locks.read(user);
            if lock_info.lock_until == 0 {
                return true;
            }
            let current_timestamp = get_block_timestamp();
            current_timestamp >= lock_info.lock_until
        }

        // VesuRebalance compatible functions
        fn rebalance(ref self: ContractState, actions: Array<Action>) {
            self.common.assert_not_paused();
            self._collect_fees(self.total_supply());

            let (yield_before_rebalance, _) = self.compute_yield();
            self._rebal_loop(actions);
            let (yield_after_rebalance, _) = self.compute_yield();

            let this = get_contract_address();
            assert(yield_after_rebalance >= yield_before_rebalance, Errors::INVALID_YIELD);
            assert(ERC20Helper::balanceOf(self.asset(), this) == 0, Errors::UNUTILIZED_ASSET);
            self._assert_max_weights();

            self
                .emit(
                    Rebalance {
                        yield_before: yield_before_rebalance.try_into().unwrap(),
                        yield_after: yield_after_rebalance.try_into().unwrap()
                    }
                );
        }

        fn rebalance_weights(ref self: ContractState, actions: Array<Action>) {
            self.common.assert_relayer_role();
            self.common.assert_not_paused();

            self._collect_fees(self.total_supply());
            self._rebal_loop(actions);

            let this = get_contract_address();
            self._assert_max_weights();
            assert(ERC20Helper::balanceOf(self.asset(), this) == 0, Errors::UNUTILIZED_ASSET);
        }

        fn emergency_withdraw(ref self: ContractState, users_to_burn: Array<ContractAddress>) {
            self.common.assert_emergency_actor_role();
            
            // First, withdraw all funds from pools
            let allowed_pools = self.get_allowed_pools();
            let mut i = 0;
            loop {
                if (i == allowed_pools.len()) {
                    break;
                }

                self.emergency_withdraw_pool(i.try_into().unwrap());
                i += 1;
            };
            
            // Then, burn shares for all specified users
            let mut j = 0;
            loop {
                if (j == users_to_burn.len()) {
                    break;
                }
                
                let user = *users_to_burn.at(j);
                let user_balance = self.erc20.balance_of(user);
                
                if user_balance > 0 {
                    self._emergency_burn_user_shares(user, user_balance);
                }
                
                j += 1;
            };
        }

        fn emergency_withdraw_pool(ref self: ContractState, pool_index: u32) {
            self.common.assert_emergency_actor_role();
            let this = get_contract_address();
            let allowed_pools = self.get_allowed_pools();
            let pool_info = *allowed_pools.at(pool_index);
            let mut v_token = pool_info.v_token;

            let withdraw_amount = IERC4626Dispatcher { contract_address: v_token }
                .max_withdraw(this);

            if (withdraw_amount == 0) {
                return;
            }
            IERC4626Dispatcher { contract_address: v_token }.withdraw(withdraw_amount, this, this);
        }

        /// @notice Emergency withdraw for a specific user: withdraws their assets from pools and burns their shares
        /// @dev Only callable by emergency actor role. This function:
        /// 1. Gets the user's shares balance
        /// 2. Converts shares to assets using preview_redeem
        /// 3. Withdraws those assets from pools proportionally (to the contract)
        /// 4. Transfers the assets to the user
        /// 5. Burns the user's shares
        /// 6. Clears their lock info
        /// @param user The user address whose funds should be withdrawn and shares burned
        fn emergency_withdraw_user(ref self: ContractState, user: ContractAddress) {
            self.common.assert_emergency_actor_role();
            
            // Get user's shares balance
            let user_shares = self.erc20.balance_of(user);
            if user_shares == 0 {
                return;
            }
            
            // Convert shares to assets (using preview_redeem to account for fees)
            let assets_to_withdraw = self.preview_redeem(user_shares);
            if assets_to_withdraw == 0 {
                // If no assets to withdraw, just burn shares and clear lock
                self._emergency_burn_user_shares(user, user_shares);
                return;
            }
            
            // Withdraw assets from pools proportionally (they go to the contract)
            let allowed_pools = self.get_allowed_pools();
            let total_assets = self.total_assets();
            
            // Calculate how much to withdraw from each pool based on user's share of total assets
            let user_share_of_total = if total_assets > 0 {
                (assets_to_withdraw * 10000) / total_assets
            } else {
                0
            };
            
            let mut remaining_assets = assets_to_withdraw;
            let mut i = 0;
            loop {
                if (i == allowed_pools.len() || remaining_assets == 0) {
                    break;
                }
                
                let pool_info = *allowed_pools.at(i);
                let v_token = pool_info.v_token;
                
                // Calculate user's portion in this pool
                let v_token_bal = ERC20Helper::vtoken_balance_of(v_token, get_contract_address());
                let pool_asset_value = if total_assets > 0 {
                    (v_token_bal * user_share_of_total) / 10000
                } else {
                    0
                };
                
                // Withdraw up to the calculated amount or remaining assets, whichever is smaller
                let withdraw_from_pool = if pool_asset_value <= remaining_assets {
                    pool_asset_value
                } else {
                    remaining_assets
                };
                
                if withdraw_from_pool > 0 {
                    let withdrawn = self._perform_withdraw_max_possible(
                        pool_info.pool_id,
                        v_token,
                        withdraw_from_pool
                    );
                    remaining_assets -= withdrawn;
                }
                
                i += 1;
            };
            
            // Now burn the user's shares and clear lock info BEFORE transferring assets
            // This ensures the shares are burned even if transfer fails
            self._emergency_burn_user_shares(user, user_shares);
            
            // Transfer the withdrawn assets to the user
            let asset = self.asset();
            ERC20Helper::transfer(asset, user, assets_to_withdraw);
        }

        /// @notice Transfers assets (WBTC) from the contract to a receiver address
        /// @dev Only callable by emergency actor role. Used to extract assets after emergency withdraw.
        /// @param receiver The address that will receive the assets
        /// @param amount The amount of assets to transfer
        fn emergency_transfer_asset(
            ref self: ContractState,
            receiver: ContractAddress,
            amount: u256
        ) {
            self.common.assert_emergency_actor_role();
            let asset = self.asset();
            ERC20Helper::transfer(asset, receiver, amount);
        }

        /// @notice Burns shares for a user after emergency withdraw and clears their lock info
        /// @dev Only callable by emergency actor role. Used to clean up shares after emergency withdraw.
        /// This function should be called after emergency_withdraw to:
        /// 1. Burn the user's shares (reducing total_supply)
        /// 2. Clear their lock info (reset locked_shares and lock_until)
        /// 3. Update reward_share state
        /// @param user The user address whose shares should be burned
        /// @param shares The amount of shares to burn (if 0, burns all user's shares)
        fn emergency_burn_shares(
            ref self: ContractState,
            user: ContractAddress,
            shares: u256
        ) {
            self.common.assert_emergency_actor_role();
            
            // Get user's current balance and lock info
            let user_balance = self.erc20.balance_of(user);
            
            // Determine how many shares to burn
            let shares_to_burn = if shares == 0 {
                user_balance
            } else {
                assert(shares <= user_balance, Errors::INVALID_BALANCE);
                shares
            };
            
            self._emergency_burn_user_shares(user, shares_to_burn);
        }

        fn compute_yield(self: @ContractState) -> (u256, u256) {
            let allowed_pools = self._get_pool_data();
            let mut i = 0;
            let mut yield_sum = 0;
            let mut amount_sum = 0;
            loop {
                if (i == allowed_pools.len()) {
                    break;
                }
                let pool = *allowed_pools.at(i);
                let interest_curr_pool = self._interest_rate_per_pool(pool.pool_id);
                let amount_in_pool = self._calculate_amount_in_pool(pool.v_token);
                yield_sum += (interest_curr_pool * amount_in_pool);
                amount_sum += amount_in_pool;
                i += 1;
            };

            ((yield_sum / amount_sum), amount_sum)
        }

        fn harvest(
            ref self: ContractState,
            rewardsContract: ContractAddress,
            claim: Claim,
            proof: Span<felt252>,
            swapInfo: AvnuMultiRouteSwap
        ) {
            self.common.assert_not_paused();
            self.common.assert_relayer_role();
            self._collect_fees(self.total_supply());

            let vesuSettings = SNFStyleClaimSettings { rewardsContract: rewardsContract, };
            let config = HarvestConfig {};
            let snfSettings = SNFStyleClaimSettings {
                rewardsContract: 0.try_into().unwrap()
            };

            let from_token = swapInfo.token_from_address;
            let to_token = swapInfo.token_to_address;
            let from_amount = swapInfo.token_from_amount;
            assert(to_token == self.asset(), Errors::INVALID_ASSET);

            let pre_bal = self.total_assets();
            config
                .simple_harvest(
                    ref self,
                    vesuSettings,
                    claim,
                    proof,
                    snfSettings,
                    swapInfo,
                    IPriceOracleDispatcher { contract_address: self.oracle.read() }
                );
            let post_bal = self.total_assets();
            assert(post_bal > pre_bal, Errors::INVALID_HARVEST);

            let from_amount = if (from_token == to_token) {
                post_bal - pre_bal
            } else {
                from_amount
            };
            self
                .emit(
                    HarvestEvent {
                        rewardToken: from_token,
                        rewardAmount: from_amount,
                        baseToken: to_token,
                        baseAmount: post_bal - pre_bal,
                    }
                );
        }

        fn set_settings(ref self: ContractState, settings: Settings) {
            self.common.assert_governor_role();
            self.settings.write(settings);
        }

        fn set_allowed_pools(ref self: ContractState, pools: Array<PoolProps>) {
            self.common.assert_governor_role();
            self._set_pool_settings(pools);
        }

        fn set_incentives_off(ref self: ContractState) {
            self.common.assert_governor_role();
            self.is_incentives_on.write(false);
        }

        fn set_lock_period(ref self: ContractState, lock_period_seconds: u64) {
            self.common.assert_governor_role();
            let min_lock = self.min_lock_period.read();
            let max_lock = self.max_lock_period.read();
            assert(lock_period_seconds >= min_lock, Errors::LOCK_PERIOD_TOO_SHORT);
            assert(lock_period_seconds <= max_lock, Errors::LOCK_PERIOD_EXCEEDED);
            self.default_lock_period.write(lock_period_seconds);
        }

        fn set_min_lock_period(ref self: ContractState, min_lock_period_seconds: u64) {
            self.common.assert_governor_role();
            let default_lock = self.default_lock_period.read();
            let max_lock = self.max_lock_period.read();
            assert(min_lock_period_seconds <= default_lock, Errors::INVALID_LOCK_PERIOD);
            assert(min_lock_period_seconds <= max_lock, Errors::INVALID_LOCK_PERIOD);
            self.min_lock_period.write(min_lock_period_seconds);
        }

        fn set_max_lock_period(ref self: ContractState, max_lock_period_seconds: u64) {
            self.common.assert_governor_role();
            let default_lock = self.default_lock_period.read();
            let min_lock = self.min_lock_period.read();
            assert(max_lock_period_seconds >= default_lock, Errors::INVALID_LOCK_PERIOD);
            assert(max_lock_period_seconds >= min_lock, Errors::INVALID_LOCK_PERIOD);
            self.max_lock_period.write(max_lock_period_seconds);
        }

        fn get_settings(self: @ContractState) -> Settings {
            self.settings.read()
        }

        fn get_allowed_pools(self: @ContractState) -> Array<PoolProps> {
            self._get_pool_data()
        }

        fn get_previous_index(self: @ContractState) -> u128 {
            self.previous_index.read()
        }

        fn get_lock_period(self: @ContractState) -> u64 {
            self.default_lock_period.read()
        }

        fn get_min_lock_period(self: @ContractState) -> u64 {
            self.min_lock_period.read()
        }

        fn get_max_lock_period(self: @ContractState) -> u64 {
            self.max_lock_period.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl of InternalTrait {
        fn _assert_not_locked(self: @ContractState, owner: ContractAddress, _amount: u256) {
            let lock_info = self.user_locks.read(owner);
            if lock_info.lock_until == 0 {
                return;
            }

            let current_timestamp = get_block_timestamp();
            assert(current_timestamp >= lock_info.lock_until, Errors::STILL_LOCKED);
            
            // Once lock period has passed, user can withdraw any amount
            // The locked_shares are informational for tracking purposes
        }

        /// @notice Internal function to burn user shares and clear lock info
        /// @dev This is called by emergency_withdraw and emergency_burn_shares
        fn _emergency_burn_user_shares(
            ref self: ContractState,
            user: ContractAddress,
            shares_to_burn: u256
        ) {
            if shares_to_burn == 0 {
                return;
            }
            
            // Get user's lock info
            let lock_info = self.user_locks.read(user);
            
            // Update lock info: reduce locked_shares proportionally
            let new_locked_shares = if lock_info.locked_shares > 0 && lock_info.locked_shares >= shares_to_burn {
                lock_info.locked_shares - shares_to_burn
            } else {
                0
            };
            
            // If all locked shares are burned, reset lock
            let new_lock_info = if new_locked_shares == 0 {
                LockInfo { lock_until: 0, locked_shares: 0 }
            } else {
                LockInfo { 
                    lock_until: lock_info.lock_until, 
                    locked_shares: new_locked_shares 
                }
            };
            
            self.user_locks.write(user, new_lock_info);
            
            // Update reward shares before burning
            self._handle_reward_shares(user, 0, shares_to_burn);
            
            // Burn the shares
            self.erc20.burn(user, shares_to_burn);
            
            self.emit(FundsUnlocked {
                user: user,
                shares: shares_to_burn
            });
        }

        fn _handle_reward_shares(
            ref self: ContractState,
            from: ContractAddress,
            unminted_shares: u256,
            minted_shares: u256
        ) {
            if (from.is_zero()) {
                return;
            }

            let (additional_shares, last_block, pending_round_points) = self
                .reward_share
                .get_additional_shares(from);

            let additional_u256: u256 = additional_shares.try_into().unwrap();
            if (self.is_incentives_on.read()) {
                let user_shares = self.erc20.balance_of(from);

                let mut new_shares = user_shares + additional_u256 - unminted_shares;
                let total_supply = self.total_supply() - minted_shares;
                self
                    .reward_share
                    .update_user_rewards(
                        from,
                        new_shares.try_into().unwrap(),
                        additional_shares,
                        last_block,
                        pending_round_points,
                        total_supply.try_into().unwrap()
                    );
            }

            if (additional_u256 > 0) {
                self.erc20.mint(from, additional_shares.try_into().unwrap());
            }
        }

        fn _assert_max_weights(self: @ContractState) {
            let total_amount = self.total_assets();
            let allowed_pools = self._get_pool_data();
            let mut i = 0;
            loop {
                if (i == allowed_pools.len()) {
                    break;
                }
                let pool = *allowed_pools.at(i);
                let asset_in_pool = self._calculate_amount_in_pool(pool.v_token);
                let asset_basis: u32 = ((asset_in_pool * 10000) / total_amount).try_into().unwrap();
                assert(asset_basis <= pool.max_weight, Errors::MAX_WEIGHT_EXCEEDED);
                i += 1;
            }
        }

        fn _calculate_amount_in_pool(self: @ContractState, v_token: ContractAddress) -> u256 {
            let this = get_contract_address();
            let v_token_bal = ERC20Helper::vtoken_balance_of(v_token, this);
            IERC4626Dispatcher { contract_address: v_token }.convert_to_assets(v_token_bal)
        }

        fn _interest_rate_per_pool(self: @ContractState, pool_id: ContractAddress) -> u256 {
            let asset = self.asset();
            let pool = IPoolDispatcher { contract_address: pool_id };
            let utilization = pool.utilization(asset);
            let asset_config = pool.asset_config(asset);
            let interest_rate = pool.interest_rate(
                asset,
                utilization,
                asset_config.last_updated,
                asset_config.last_full_utilization_rate
            );
            (interest_rate * utilization)
        }

        fn _set_pool_settings(ref self: ContractState, allowed_pools: Array<PoolProps>,) {
            let old_pools = self._get_pool_data();
            let old_default_pool_index = self.settings.read().default_pool_index;

            assert(allowed_pools.len() > 0, Errors::INVALID_POOL_LENGTH);
            let mut pools_str = self.allowed_pools.read();
            pools_str.clean();
            pools_str.append_span(allowed_pools.span()).unwrap();
            assert(
                self.allowed_pools.read().len() == allowed_pools.len(), Errors::INVALID_POOL_LENGTH
            );

            let mut old_index = 0;
            loop {
                if old_index == old_pools.len() {
                    break;
                }
                let pool = *old_pools.at(old_index);
                let mut new_index = 0;
                let mut found = false;
                loop {
                    if new_index == allowed_pools.len() {
                        break;
                    }
                    let new_pool = *allowed_pools.at(new_index);
                    if pool.pool_id == new_pool.pool_id {
                        found = true;

                        if (old_index == (old_default_pool_index).into()) {
                            self
                                .settings
                                .write(
                                    Settings {
                                        default_pool_index: new_index.try_into().unwrap(),
                                        ..self.settings.read()
                                    }
                                );
                        }
                        break;
                    }
                    new_index += 1;
                };

                if (!found) {
                    let v_token = pool.v_token;
                    let v_token_bal = ERC20Helper::vtoken_balance_of(v_token, get_contract_address());
                    assert(v_token_bal == 0, Errors::INVALID_POOL_CONFIG);
                }
                old_index += 1;
            };
        }

        fn _get_pool_data(self: @ContractState) -> Array<PoolProps> {
            let mut pool_ids_array = self.allowed_pools.read().array().unwrap();
            pool_ids_array
        }

        fn _compute_assets(self: @ContractState) -> u256 {
            let mut assets: u256 = 0;
            let pool_ids_array = self._get_pool_data();
            let mut i = 0;
            loop {
                if i == pool_ids_array.len() {
                    break;
                }
                let v_token = *pool_ids_array.at(i).v_token;
                let asset_conv = self._calculate_amount_in_pool(v_token);
                assets += asset_conv;
                i += 1;
            };
            assets
        }

        fn _collect_fees(ref self: ContractState, previous_total_supply: u256) {
            let this = get_contract_address();
            let prev_index = self.previous_index.read();
            let assets = self.total_assets();
            let total_supply = self.total_supply();
            
            if total_supply == 0 {
                let initial_index: u256 = DEFAULT_INDEX.into();
                self.previous_index.write(initial_index.try_into().unwrap());
                return;
            }
            
            let curr_index = (assets * DEFAULT_INDEX.into()) / total_supply;
            if curr_index < prev_index.into() {
                let new_index = ((assets - 1) * DEFAULT_INDEX.into()) / total_supply;
                self.previous_index.write(new_index.try_into().unwrap());
                return;
            }
            let index_diff = curr_index.try_into().unwrap() - prev_index;

            let numerator: u256 = previous_total_supply
                * index_diff.into()
                * self.settings.fee_bps.read().into();
            let denominator: u256 = 10000 * DEFAULT_INDEX.into();
            let fee = if (numerator <= 1) {
                0
            } else {
                (numerator - 1) / denominator
            };
            if fee == 0 {
                return;
            }

            let mut fee_loop = fee;
            let allowed_pools = self._get_pool_data();
            let fee_receiver = self.settings.fee_receiver.read();
            let mut i = 0;
            loop {
                if i == allowed_pools.len() {
                    break;
                }
                let v_token = *allowed_pools.at(i).v_token;
                let vault_disp = IERC4626Dispatcher { contract_address: v_token };
                let v_shares_required = vault_disp.convert_to_shares(fee_loop.into());
                let v_token_bal = ERC20Helper::vtoken_balance_of(v_token, this);
                if v_shares_required <= v_token_bal {
                    ERC20Helper::vtoken_transfer(v_token, fee_receiver, v_shares_required);
                    break;
                } else {
                    ERC20Helper::vtoken_transfer(v_token, fee_receiver, v_token_bal);
                    fee_loop -= vault_disp.convert_to_assets(v_token_bal).try_into().unwrap();
                }
                i += 1;
            };

            let new_index = if total_supply == 0 {
                DEFAULT_INDEX.into()
            } else {
                ((assets - fee.into() - 1) * DEFAULT_INDEX.into()) / total_supply
            };
            self.previous_index.write(new_index.try_into().unwrap());

            self
                .emit(
                    CollectFees {
                        fee_collected: fee.try_into().unwrap(), fee_collector: fee_receiver
                    }
                );
        }

        fn _rebal_loop(ref self: ContractState, action_array: Array<Action>) {
            let mut i = 0;
            loop {
                if i == action_array.len() {
                    break;
                }
                let mut action = action_array.at(i);
                self._action(*action);
                i += 1;
            }
        }

        fn _action(ref self: ContractState, action: Action) {
            let this = get_contract_address();
            let allowed_pools = self.get_allowed_pools();
            let mut i = 0;
            let mut v_token = allowed_pools.at(i).v_token;
            loop {
                assert(i != allowed_pools.len(), Errors::INVALID_POOL_ID);
                if *allowed_pools.at(i).pool_id == action.pool_id {
                    v_token = allowed_pools.at(i).v_token;
                    break;
                }
                i += 1;
            };

            match action.feature {
                Feature::DEPOSIT => {
                    ERC20Helper::vtoken_approve(self.asset(), *v_token, action.amount);
                    IERC4626Dispatcher { contract_address: *v_token }.deposit(action.amount, this);
                },
                Feature::WITHDRAW => {
                    IERC4626Dispatcher { contract_address: *v_token }
                        .withdraw(action.amount, this, this);
                },
            };
        }

        fn _perform_withdraw_max_possible(
            ref self: ContractState, pool_id: ContractAddress, v_token: ContractAddress, amount: u256
        ) -> u256 {
            let this = get_contract_address();
            let max_withdraw = IERC4626Dispatcher { contract_address: v_token }.max_withdraw(this);
            let withdraw_amount = if max_withdraw >= amount {
                amount
            } else {
                max_withdraw
            };

            if (withdraw_amount == 0) {
                return 0;
            }

            IERC4626Dispatcher { contract_address: v_token }.withdraw(withdraw_amount, this, this);

            return withdraw_amount;
        }
    }

    #[abi(embed_v0)]
    impl LockToEarnBondERC4626Impl of IERC4626<ContractState> {
        fn asset(self: @ContractState) -> ContractAddress {
            self.erc4626.asset()
        }

        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.convert_to_assets(shares)
        }

        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.convert_to_shares(assets)
        }

        fn deposit(
            ref self: ContractState, assets: u256, receiver: starknet::ContractAddress
        ) -> u256 {
            // Use deposit_locked by default
            self.deposit_locked(assets, receiver)
        }

        fn max_deposit(self: @ContractState, receiver: ContractAddress) -> u256 {
            self.erc4626.max_deposit(receiver)
        }

        fn max_mint(self: @ContractState, receiver: starknet::ContractAddress) -> u256 {
            self.erc4626.max_mint(receiver)
        }

        fn max_redeem(self: @ContractState, owner: starknet::ContractAddress) -> u256 {
            self.erc4626.max_redeem(owner)
        }

        fn max_withdraw(self: @ContractState, owner: starknet::ContractAddress) -> u256 {
            // Check if user has unlocked shares
            if (!self.can_withdraw(owner)) {
                return 0;
            }
            self.erc4626.max_withdraw(owner)
        }

        fn mint(
            ref self: ContractState, shares: u256, receiver: starknet::ContractAddress
        ) -> u256 {
            let assets = self.preview_mint(shares);
            self.deposit_locked(assets, receiver)
        }

        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_deposit(assets)
        }

        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.preview_mint(shares)
        }

        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            self.erc4626.preview_redeem(shares)
        }

        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            self.erc4626.preview_withdraw(assets)
        }

        fn redeem(
            ref self: ContractState,
            shares: u256,
            receiver: starknet::ContractAddress,
            owner: starknet::ContractAddress
        ) -> u256 {
            // Check lock period first
            self._assert_not_locked(owner, shares);
            // Then call the ERC4626 component's internal redeem
            self.erc4626.redeem(shares, receiver, owner)
        }

        fn total_assets(self: @ContractState) -> u256 {
            let bal = ERC20Helper::balanceOf(self.asset(), get_contract_address());
            self._compute_assets() + bal
        }

        fn withdraw(
            ref self: ContractState,
            assets: u256,
            receiver: starknet::ContractAddress,
            owner: starknet::ContractAddress
        ) -> u256 {
            // Check lock period first - need to convert assets to shares for the check
            let shares = self.preview_withdraw(assets);
            self._assert_not_locked(owner, shares);
            // Then call the ERC4626 component's internal withdraw
            self.erc4626.withdraw(assets, receiver, owner)
        }
    }

    #[abi(embed_v0)]
    impl LockToEarnBondERC20Impl of IERC20Mixin<ContractState> {
        fn total_supply(self: @ContractState) -> u256 {
            let unminted_shares = self.reward_share.get_total_unminted_shares();
            let total_supply = self.erc20.total_supply();
            let total_supply: u256 = total_supply + unminted_shares.try_into().unwrap();
            total_supply
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            let (additional_shares, _, _) = self.reward_share.get_additional_shares(account);
            self.erc20.balance_of(account) + additional_shares.into()
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20.allowance(owner, spender)
        }
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.erc20.transfer(recipient, amount)
        }
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            self.erc20.transfer_from(sender, recipient, amount)
        }
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20.approve(spender, amount)
        }

        fn name(self: @ContractState) -> ByteArray {
            self.erc4626.name()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc4626.symbol()
        }

        fn decimals(self: @ContractState) -> u8 {
            ERC20Helper::decimals(self.asset())
        }

        fn totalSupply(self: @ContractState) -> u256 {
            self.total_supply()
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            self.transfer_from(sender, recipient, amount)
        }
    }

    impl ERC4626DefaultNoFees of ERC4626Component::FeeConfigTrait<ContractState> {}

    impl ERC4626DefaultLimits<ContractState> of ERC4626Component::LimitConfigTrait<ContractState> {}

    impl DefaultConfig of ERC4626Component::ImmutableConfig {
        const UNDERLYING_DECIMALS: u8 =
            0;
        const DECIMALS_OFFSET: u8 = 0;
    }

    impl HooksImpl of ERC4626Component::ERC4626HooksTrait<ContractState> {
        fn after_deposit(
            ref self: ERC4626Component::ComponentState<ContractState>, assets: u256, shares: u256,
        ) {
            let mut contract_state = self.get_contract_mut();
            contract_state.common.assert_not_paused();

            let pool_ids_array = contract_state._get_pool_data();
            let this = get_contract_address();
            let default_pool_index = contract_state.settings.default_pool_index.read();
            let v_token = *pool_ids_array.at(default_pool_index.into()).v_token;
            ERC20Helper::vtoken_approve(self.asset(), v_token, assets);
            IERC4626Dispatcher { contract_address: v_token }.deposit(assets, this);
            let current_total_supply = contract_state.total_supply();
            let fee_shares = if current_total_supply > shares {
                current_total_supply - shares
            } else {
                0
            };
            contract_state._collect_fees(fee_shares);
        }

        fn before_withdraw(
            ref self: ERC4626Component::ComponentState<ContractState>, assets: u256, shares: u256
        ) {
            let mut contract_state = self.get_contract_mut();
            contract_state.common.assert_not_paused();
            contract_state._collect_fees(contract_state.total_supply());
            let mut pool_ids_array = contract_state._get_pool_data();

            let mut remaining_amount = assets;
            let mut i = 0;
            loop {
                if i == pool_ids_array.len() {
                    break;
                }
                let withdrawn_amount = contract_state
                    ._perform_withdraw_max_possible(
                        *pool_ids_array.at(i).pool_id,
                        *pool_ids_array.at(i).v_token,
                        remaining_amount
                    );
                remaining_amount -= withdrawn_amount;
                if (remaining_amount == 0) {
                    break;
                }
                i += 1;
            };
            assert(remaining_amount == 0, Errors::INVALID_BALANCE);
        }
    }

    impl ERC20HooksImpl of ERC20Component::ERC20HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let mut state = self.get_contract_mut();
            state._handle_reward_shares(from, amount, 0);
        }

        fn after_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let mut state = self.get_contract_mut();
            state._handle_reward_shares(recipient, 0, amount);
        }
    }

    impl HarvestHooksImpl of HarvestHooksTrait<ContractState> {
        fn before_update(ref self: ContractState) -> HarvestBeforeHookResult {
            HarvestBeforeHookResult { baseToken: self.asset() }
        }

        fn after_update(ref self: ContractState, token: ContractAddress, amount: u256) {
            let fee = (amount * self.settings.fee_bps.read().into()) / 10000;
            if (fee > 0) {
                let fee_receiver = self.settings.fee_receiver.read();
                ERC20Helper::transfer(token, fee_receiver, fee);
            }
            let amt = amount - fee;
            let shares = self.convert_to_shares(amt);

            let pool_ids_array = self._get_pool_data();
            let default_pool_index = self.settings.default_pool_index.read();
            let v_token = *pool_ids_array.at(default_pool_index.into()).v_token;
            ERC20Helper::vtoken_approve(self.asset(), v_token, amt);
            IERC4626Dispatcher { contract_address: v_token }.deposit(amt, get_contract_address());

            let total_shares = self.total_supply();
            self
                .reward_share
                .update_harvesting_rewards(
                    amt.try_into().unwrap(),
                    shares.try_into().unwrap(),
                    total_shares.try_into().unwrap()
                );
        }
    }
}

