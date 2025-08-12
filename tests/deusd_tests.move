#[test_only]
module elixir::deusd_tests;

use elixir::deusd::{Self, DeUSDConfig, DEUSD};
use sui::test_scenario;
use std::unit_test::assert_eq;
use elixir::config;
use sui::coin::{Self, Coin};

const BOB: address = @0xb0b;

#[test]
fun test_mint_success() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, BOB, amount, &global_config, ts.ctx());
        
        // Check that BOB received the coin
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());

        coin::burn_for_testing(minted_coin);
    };

    config::destroy_for_test(global_config);
    test_scenario::return_shared(deusd_config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = config::EPackageVersionMismatch)]
fun test_mint_fail_if_package_version_mismatch() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_with_custom_version_for_test(
        config::get_package_version() + 1,
        ts.ctx(),
    );
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, BOB, amount, &global_config, ts.ctx());

        // This should fail due to package version mismatch, so we won't reach here
    };

    // Simulate a package version mismatch
    config::destroy_for_test(global_config);
    ts.next_tx(@elixir);

    test_scenario::return_shared(deusd_config);
    ts.end();
}


#[test]
#[expected_failure(abort_code = deusd::EZeroAddress)]
fun test_mint_fail_if_to_zero_address() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, @0x0, amount, &global_config, ts.ctx());

        // This should fail due to zero address, so we won't reach here
    };

    config::destroy_for_test(global_config);
    test_scenario::return_shared(deusd_config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAmount)]
fun test_mint_fail_if_zero_amount() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        deusd::mint(&mut deusd_config, BOB, 0, &global_config, ts.ctx());

        // This should fail due to zero amount, so we won't reach here
    };

    config::destroy_for_test(global_config);
    test_scenario::return_shared(deusd_config);
    ts.end();
}

#[test]
fun test_burn_success() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, BOB, amount, &global_config, ts.ctx());
        
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());

        deusd::burn(&mut deusd_config, minted_coin, &global_config, ts.ctx());
    };

    config::destroy_for_test(global_config);
    test_scenario::return_shared(deusd_config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = config::EPackageVersionMismatch)]
fun test_burn_fail_if_package_version_mismatch() {
    let mut ts = test_scenario::begin(@elixir);

    // First create a good config to mint the coin
    let good_global_config = config::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    // Mint with good config first
    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, BOB, amount, &good_global_config, ts.ctx());
    };

    // Now create bad config for burn test
    let bad_global_config = config::create_with_custom_version_for_test(
        config::get_package_version() + 1,
        ts.ctx(),
    );

    {
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        
        // This should fail due to package version mismatch
        deusd::burn(&mut deusd_config, minted_coin, &bad_global_config, ts.ctx());
    };

    config::destroy_for_test(good_global_config);
    config::destroy_for_test(bad_global_config);
    test_scenario::return_shared(deusd_config);
    ts.end();
}
