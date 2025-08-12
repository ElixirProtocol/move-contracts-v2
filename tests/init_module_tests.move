#[test_only]
module elixir::init_module_tests;

use elixir::deusd_minting::DeUSDMintingManagement;
use elixir::config::GlobalConfig;
use elixir::admin_cap::AdminCap;
use elixir::deusd::{DeUSDConfig};
use sui::test_scenario;

#[test]
fun test_init_modules_success() {
    let mut ts = test_scenario::begin(@elixir);

    elixir::admin_cap::init_for_test(ts.ctx());
    elixir::config::init_for_test(ts.ctx());
    elixir::deusd::init_for_test(ts.ctx());
    elixir::deusd_minting::init_for_test(ts.ctx());
    elixir::deusd_lp_staking::init_for_test(ts.ctx());

    ts.next_tx(@admin);
    let admin_cap: AdminCap = ts.take_from_address(@admin);

    ts.next_tx(@elixir);
    let global_config: GlobalConfig = ts.take_shared();
    let deusd_config: DeUSDConfig = ts.take_shared();
    let deusd_minting_management: DeUSDMintingManagement = ts.take_shared();
    let deusd_lp_staking_management: elixir::deusd_lp_staking::DeUSDLPStakingManagement = ts.take_shared();

    test_scenario::return_to_address(@admin, admin_cap);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    test_scenario::return_shared(deusd_minting_management);
    test_scenario::return_shared(deusd_lp_staking_management);
    ts.end();
}

