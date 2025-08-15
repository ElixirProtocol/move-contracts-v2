#[test_only]
module elixir::test_utils;

// === Imports ===

use elixir::deusd;
use elixir::deusd_minting::DeUSDMintingManagement;
use elixir::deusd::DeUSDConfig;
use elixir::sdeusd::SdeUSDManagement;
use elixir::staking_rewards_distributor::{Self, StakingRewardsDistributor};
use elixir::admin_cap::AdminCap;
use elixir::config::GlobalConfig;
use sui::test_scenario;
use elixir::admin_cap;
use elixir::deusd_minting;
use elixir::sdeusd;
use elixir::config;

// === Public Functions ===

public fun setup_global_config(ts: &mut test_scenario::Scenario, admin: address): (GlobalConfig, AdminCap) {
    config::init_for_test(ts.ctx());
    admin_cap::init_for_test(ts.ctx());

    ts.next_tx(admin);
    let global_config = ts.take_shared<GlobalConfig>();
    let admin_cap = ts.take_from_sender<AdminCap>();

    (global_config, admin_cap)
}

public fun setup_deusd(ts: &mut test_scenario::Scenario, admin: address): DeUSDConfig {
    deusd::init_for_test(ts.ctx());

    ts.next_tx(admin);
    ts.take_shared<DeUSDConfig>()
}

public fun setup_deusd_minting(ts: &mut test_scenario::Scenario, admin: address): DeUSDMintingManagement {
    deusd_minting::init_for_test(ts.ctx());

    ts.next_tx(admin);
    ts.take_shared<DeUSDMintingManagement>()
}

public fun setup_sdeusd(ts: &mut test_scenario::Scenario, admin: address): SdeUSDManagement {
    sdeusd::init_for_test(ts.ctx());

    ts.next_tx(admin);
    ts.take_shared<SdeUSDManagement>()
}

public fun setup_staking_rewards_distributor(ts: &mut test_scenario::Scenario, admin: address): StakingRewardsDistributor {
    staking_rewards_distributor::init_for_test(ts.ctx());

    ts.next_tx(admin);
    ts.take_shared<StakingRewardsDistributor>()
}