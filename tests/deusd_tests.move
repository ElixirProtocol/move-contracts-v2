#[test_only]
module elixir::deusd_tests;

use elixir::deusd::{Self, Config};
use sui::test_scenario;
use std::unit_test::assert_eq;
use elixir::package_version;
use sui::coin;

const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;

#[test]
fun test_set_minter_success() {
    let mut ts = test_scenario::begin(@elixir);

    let admin_cap = elixir::admin_cap::create_for_test(ts.ctx());
    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut config: Config = ts.take_shared();

    {
        ts.next_tx(@admin);
        deusd::set_minter(&admin_cap, &mut config, BOB, &version, ts.ctx());

        ts.next_tx(@admin);
        deusd::set_minter(&admin_cap, &mut config, ALICE, &version, ts.ctx());
    };

    elixir::admin_cap::destroy_for_test(admin_cap);
    package_version::destroy_for_test(version);
    test_scenario::return_shared(config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAddress)]
fun test_set_minter_fail_if_minter_zero_address() {
    let mut ts = test_scenario::begin(@elixir);

    let admin_cap = elixir::admin_cap::create_for_test(ts.ctx());
    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut management: Config = ts.take_shared();

    {
        ts.next_tx(@admin);
        deusd::set_minter(&admin_cap, &mut management, @0x0, &version, ts.ctx());
    };

    elixir::admin_cap::destroy_for_test(admin_cap);
    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_mint_success() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut management: Config = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        let minted_coin = deusd::mint(&mut management, BOB, amount, &version, ts.ctx());
        assert_eq!(amount, minted_coin.value());

        coin::burn_for_testing(minted_coin);
    };

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}


#[test]
#[expected_failure(abort_code = deusd::ENotMinter)]
fun test_mint_fail_if_not_minter() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut management: Config = ts.take_shared();

    {
        ts.next_tx(BOB);
        let amount = 10_000_000_000_000;
        let minted_coin = deusd::mint(&mut management, BOB, amount, &version, ts.ctx());

        coin::burn_for_testing(minted_coin);
    };

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAddress)]
fun test_mint_fail_if_to_zero_address() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut management: Config = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        let minted_coin = deusd::mint(&mut management, @0x0, amount, &version, ts.ctx());

        coin::burn_for_testing(minted_coin);
    };

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAmount)]
fun test_mint_fail_if_zero_amount() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut management: Config = ts.take_shared();

    {
        ts.next_tx(@admin);
        let minted_coin = deusd::mint(&mut management, BOB, 0, &version, ts.ctx());

        coin::burn_for_testing(minted_coin);
    };

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_burn_success() {
    let mut ts = test_scenario::begin(@elixir);

    let version = package_version::create_for_test(ts.ctx());
    deusd::init_for_test(ts.ctx());
    ts.next_tx(@elixir);
    let mut management: Config = ts.take_shared();

    {
        ts.next_tx(@admin);
        let amount = 10_000_000_000_000;
        let minted_coin = deusd::mint(&mut management, BOB, amount, &version, ts.ctx());
        assert_eq!(amount, minted_coin.value());

        ts.next_tx(BOB);
        deusd::burn(&mut management, minted_coin, &version, ts.ctx());
    };

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}
