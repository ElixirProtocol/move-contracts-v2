#[test_only]
module elixir::deusd_tests;

use elixir::deusd::{Self, DeUSDConfig, DEUSD};
use sui::test_scenario;
use std::unit_test::assert_eq;
use sui::coin::{Self, Coin};

const ADMIN: address = @0xad;
const BOB: address = @0xb0b;

#[test]
fun test_mint_success() {
    let mut ts = test_scenario::begin(ADMIN);

    deusd::init_for_test(ts.ctx());
    ts.next_tx(ADMIN);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(ADMIN);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, BOB, amount, ts.ctx());
        
        // Check that BOB received the coin
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());

        coin::burn_for_testing(minted_coin);
    };

    test_scenario::return_shared(deusd_config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAddress)]
fun test_mint_fail_if_to_zero_address() {
    let mut ts = test_scenario::begin(ADMIN);

    deusd::init_for_test(ts.ctx());
    ts.next_tx(ADMIN);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(ADMIN);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, @0x0, amount, ts.ctx());
    };

    test_scenario::return_shared(deusd_config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAmount)]
fun test_mint_fail_if_zero_amount() {
    let mut ts = test_scenario::begin(ADMIN);

    deusd::init_for_test(ts.ctx());
    ts.next_tx(ADMIN);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(ADMIN);
        deusd::mint(&mut deusd_config, BOB, 0, ts.ctx());
    };

    test_scenario::return_shared(deusd_config);
    ts.end();
}

#[test]
fun test_burn_success() {
    let mut ts = test_scenario::begin(ADMIN);

    deusd::init_for_test(ts.ctx());
    ts.next_tx(ADMIN);
    let mut deusd_config: DeUSDConfig = ts.take_shared();

    {
        ts.next_tx(ADMIN);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, BOB, amount, ts.ctx());
        
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());

        deusd::burn_from(&mut deusd_config, minted_coin, BOB);
    };

    test_scenario::return_shared(deusd_config);
    ts.end();
}
