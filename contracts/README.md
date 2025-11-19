# Numo - Cairo Smart Contracts

Numo's Cairo contracts orchestrate vaults, yield strategies, and governance controls on Starknet.  
The codebase is organized as reusable components (access control, ERC-4626 vault logic, harvester stack) and composable strategy contracts that integrate with external protocols.

## 📁 Structure

```
contracts/
├── src/
│   ├── lib.cairo                  # Module wiring
│   ├── components/
│   │   ├── accessControl.cairo    # Standalone AccessControl contract (roles + upgrades)
│   │   ├── common.cairo           # Pausable + upgradeable mixin backed by AccessControl
│   │   ├── erc4626.cairo          # Vault logic shared across strategies
│   │   ├── swap.cairo             # Avnu multi-route swap adapter
│   │   ├── vesu.cairo             # Vesu-specific helpers
│   │   └── harvester/
│   │       ├── harvester_lib.cairo
│   │       ├── reward_shares.cairo
│   │       ├── interface.cairo
│   │       └── defi_spring_default_style.cairo
│   ├── helpers/                   # Math, pow, safe decimal and ERC20 helpers
│   ├── interfaces/                # IERC4626, pools, oracle, distributor, etc.
│   ├── strategies/
│   │   ├── vesu_rebalance/        # Dynamic Vesu leveraged vault
│   │   └── lock_to_earn_bond/     # Time-locked bond vault built on Vesu pools
│   └── tests/                     # On-chain test helpers
├── Scarb.toml / Scarb.lock        # Build + dependency manifest
├── snfoundry.toml                 # Starknet Foundry config + fork presets
├── run-tests.sh / test.sh         # Helper scripts around snforge test suites
├── deploy.sh                      # Sample deployment helper
├── serialize_with_starknetjs.js   # JS calldata tooling
└── README.md
```

## 🧩 Architecture Highlights

- **AccessControl contract** (`components/accessControl.cairo`): Ownable-style contract that mints `DEFAULT_ADMIN_ROLE`, `GOVERNOR`, `RELAYER`, and `EMERGENCY_ACTOR` roles, exposes upgrade entrypoints, and emits SRC5 metadata for tooling compatibility.
- **Common component** (`components/common.cairo`): Embeddable mixin for vaults that routes pause/unpause/upgrade actions through AccessControl. It combines `Pausable`, `ReentrancyGuard`, and `Upgradeable` behaviors and centralizes role assertions.
- **ERC4626 stack** (`components/erc4626.cairo` + `helpers/ERC20Helper.cairo`): Shared implementation of deposits, withdrawals, share accounting, and metadata used by every vault strategy.
- **Harvester subsystem** (`components/harvester/*`): Configurable hooks, reward share accounting, and claim adapters (e.g., DeFi Spring default style) that automate incentive harvesting and distribution.
- **Swap adapter** (`components/swap.cairo`): Integrates the Avnu multi-route swapper so strategies can route harvested fees or rebalance collateral atomically.
- **Interfaces & helpers** (`interfaces/*`, `helpers/*`): Canonical interfaces for pools, distributors, Vesu contracts, price oracles, math utilities, and constants that keep strategies decoupled from vendor contracts.

## 🚀 Strategies

### Vesu Rebalance (`strategies/vesu_rebalance`)
- ERC-4626 vault with ERC-20 shares, reward sharing, and pausable safeguards.
- Consumes a curated list of Vesu pools (`PoolProps`) and executes `Action`-based rebalance scripts that ensure post-trade yield is non-decreasing and asset utilization is 100%.
- Emits detailed `Rebalance`, `CollectFees`, and `Harvest` events and enforces weight caps, oracle-driven pricing, and on-chain assertions for every action.

### Lock-to-Earn Bond (`strategies/lock_to_earn_bond`)
- Extends the Vesu vault logic with enforced lock periods per depositor, enabling bond-style products.
- Tracks per-user lock metadata, guards withdrawals until `lock_until`, and emits `FundsLocked`/`FundsUnlocked`.
- Reuses the same harvester, incentives toggle, and rebalance primitives as the Vesu strategy, ensuring consistent operator tooling.

## 🛠 Development

- **Prerequisites**
  - [Scarb](https://docs.swmansion.com/scarb/) ≥ 2.12 toolchain
  - [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/) (`snforge`) for fuzzing + fork tests
  - Starknet CLI (for deployments) and Node.js (for calldata utilities)

- **Build**
  ```bash
  scarb build
  ```

- **Unit & fork tests**
  ```bash
  scarb test            # Cairo native tests
  snforge test          # Uses forks configured in snfoundry.toml
  ./run-tests.sh        # Wrapper that sets env vars + tooling defaults
  ```

- **Deployment**
  ```bash
  ./deploy.sh                                       # customizable helper
  starknet deploy --contract target/dev/<name>.sierra.json
  ```
  Use the AccessControl contract as the governance root, then point each strategy's constructor to the deployed access-control address.

## 🔒 Security

- Strict role-gated upgrade, pause, rebalance, and harvest flows via `AccessControl`.
- Pausable + reentrancy-guarded vault components by default.
- Runtime assertions for pool configs, weight limits, oracle responses, and asset utilization before/after every rebalance.
- Reward claiming, swaps, and migrations executed through reviewed adapters, minimizing direct external calls.
- Emergency-actor role can pause vaults globally, while governors manage rebalances and relayers trigger automated flows.

## 📊 Monitoring & Operations

- Event surface covers rebalances, fee collection, harvests, lock/unlock transitions, and reward claims—suitable for indexing via Starknet explorers.
- Oracle + pool stats exposed through `interfaces/*` to enable off-chain TVL/APY dashboards.
- `Scarb.toml` defines multiple fork presets so operators can replay historical states before executing on mainnet.

## 🤝 Integrations

- **Vesu** lending pools for leveraged BTC/USDC positions.
- **Avnu** multi-route swap router for deterministic asset conversions.
- **Starknet** base L2, leveraging OpenZeppelin Cairo components and Alexandria libraries.
- **WBTC / ERC20** tokens via ERC4626-compatible vaults and helper utilities.

## 📝 Documentation

Additional specs, calldata recipes, and operational guides live under `contracts/docs` (coming soon). Reach out to the Numo team if you need ABI packages, deployment IDs, or integration support.

---

Developed with ❤️ by the Numo Team.