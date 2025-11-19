pub mod helpers {
    pub mod ERC20Helper;
    pub mod Math;
    pub mod pow;
    pub mod safe_decimal_math;
    pub mod constants;
}

pub mod components {
    pub mod harvester {
        pub mod harvester_lib;
        pub mod defi_spring_default_style;
        pub mod interface;
        pub mod reward_shares;
    }
    pub mod swap;
    pub mod erc4626;
    pub mod common;
    pub mod vesu;
    pub mod accessControl;
}

pub mod interfaces {
    pub mod oracle;
    pub mod common;
    pub mod IERC4626;
    pub mod IVesu;
    pub mod lendcomp;
    pub mod IDistributor;
    pub mod IPool;
}

pub mod strategies {
    pub mod vesu_rebalance {
        pub mod interface;
        pub mod vesu_rebalance;
        #[cfg(test)]
        pub mod test;
    }
    pub mod lock_to_earn_bond {
        pub mod interface;
        pub mod lock_to_earn_bond;
    }
}

#[cfg(test)]
pub mod tests {
    pub mod utils;
}
