use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::contract_address::contract_address_const;
use snforge_std::{DeclareResultTrait};
use starknet::{ContractAddress, get_contract_address};
use numo_contracts::interfaces::IDistributor::{IDistributorDispatcher};
use numo_contracts::components::harvester::defi_spring_default_style::{
    ISNFClaimTraitDispatcher
};
use numo_contracts::helpers::constants;
use numo_contracts::helpers::ERC20Helper;
use numo_contracts::helpers::pow;

pub fn deploy_access_control() -> ContractAddress {
    let cls = declare("AccessControl").unwrap().contract_class();

    let this = get_contract_address();

    let mut calldata: Array<felt252> = array![this.into(), this.into(), this.into(), this.into(),];
    let (address, _) = cls.deploy(@calldata).expect('AC deploy failed');
    return address;
}

pub fn deploy_defi_spring_ekubo() -> IDistributorDispatcher {
    let cls = declare("DefiSpringEkuboMock").unwrap().contract_class();

    let mut calldata: Array<felt252> = array![];
    let (address, _) = cls.deploy(@calldata).expect('DefiSpringEkubo deploy failed');

    // load strk into the contract
    load_strk(address);
    return IDistributorDispatcher { contract_address: address };
}

pub fn deploy_snf_spring_ekubo() -> ISNFClaimTraitDispatcher {
    let cls = declare("DefiSpringSNFMock").unwrap().contract_class();

    let mut calldata: Array<felt252> = array![];
    let (address, _) = cls.deploy(@calldata).expect('DefiSpringSNF deploy failed');

    // load strk into the contract
    load_strk(address);
    return ISNFClaimTraitDispatcher { contract_address: address };
}

pub fn load_strk(user: ContractAddress) {
    // binance address
    let source = contract_address_const::<
        0x0213c67ed78bc280887234fe5ed5e77272465317978ae86c25a71531d9332a2d
    >();
    start_cheat_caller_address(constants::STRK_ADDRESS(), source);
    ERC20Helper::transfer(constants::STRK_ADDRESS(), user, 10000 * pow::ten_pow(18));
    stop_cheat_caller_address(constants::STRK_ADDRESS());
}

pub fn load_wbtc(user: ContractAddress) {
    // binance address
    let source = contract_address_const::<
        0x0213c67ed78bc280887234fe5ed5e77272465317978ae86c25a71531d9332a2d
    >();
    start_cheat_caller_address(constants::wBTC_ADDRESS(), source);
    ERC20Helper::transfer(constants::wBTC_ADDRESS(), user, 10000 * pow::ten_pow(18));
    stop_cheat_caller_address(constants::wBTC_ADDRESS());
}
