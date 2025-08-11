#[test_only]
module elixir::deusd_tests;

use elixir::deusd::{Self, DeUSDConfig, DEUSD};
use sui::test_scenario;
use std::unit_test::assert_eq;
use elixir::package_version;
use sui::coin::{Self, Coin};

const BOB: address = @0xb0b;

#[test]
fun test_mint_success() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut config, BOB, amount, &version, ts.ctx());
        
        // Check that BOB received the coin
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());

        coin::burn_for_testing(minted_coin);
    };

    package_version::destroy_for_test(version);
    test_scenario::return_shared(config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = package_version::EPackageVersionMismatch)]
fun test_mint_fail_if_package_version_mismatch() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_with_custom_version_for_test(
        package_version::get_package_version() + 1,
        ts.ctx(),
    );
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut config, BOB, amount, &version, ts.ctx());

        // This should fail due to package version mismatch, so we won't reach here
    };

    // Simulate a package version mismatch
    package_version::destroy_for_test(version);
    ts.next_tx(@elixir);

    test_scenario::return_shared(config);
    ts.end();
}


#[test]
#[expected_failure(abort_code = deusd::EZeroAddress)]
fun test_mint_fail_if_to_zero_address() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut config, @0x0, amount, &version, ts.ctx());

        // This should fail due to zero address, so we won't reach here
    };

    package_version::destroy_for_test(version);
    test_scenario::return_shared(config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAmount)]
fun test_mint_fail_if_zero_amount() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        deusd::mint(&mut config, BOB, 0, &version, ts.ctx());

        // This should fail due to zero amount, so we won't reach here
    };

    package_version::destroy_for_test(version);
    test_scenario::return_shared(config);
    ts.end();
}

#[test]
fun test_burn_success() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut config, BOB, amount, &version, ts.ctx());
        
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());

        deusd::burn(&mut config, minted_coin, &version, ts.ctx());
    };

    package_version::destroy_for_test(version);
    test_scenario::return_shared(config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = package_version::EPackageVersionMismatch)]
fun test_burn_fail_if_package_version_mismatch() {
    let mut ts = test_scenario::begin(@elixir);

    // First create a good version to mint the coin
    let good_version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut config: DeUSDConfig = ts.take_shared();

    // Mint with good version first
    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut config, BOB, amount, &good_version, ts.ctx());
    };

    // Now create bad version for burn test
    let bad_version = package_version::create_with_custom_version_for_test(
        package_version::get_package_version() + 1,
        ts.ctx(),
    );

    {
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        
        // This should fail due to package version mismatch
        deusd::burn(&mut config, minted_coin, &bad_version, ts.ctx());
    };

    package_version::destroy_for_test(good_version);
    package_version::destroy_for_test(bad_version);
    test_scenario::return_shared(config);
    ts.end();
}
