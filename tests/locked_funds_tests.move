#[test_only]
module elixir::locked_funds_tests;

use std::type_name;
use sui::coin::{Self, Coin};
use sui::test_scenario;
use sui::test_utils::assert_eq;
use elixir::config;
use elixir::locked_funds::{Self, LockedFundsManagement};

public struct BTC has drop {}
public struct ETH has drop {}

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

#[test]
fun test_deposit_success() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    locked_funds::init_for_test(ts.ctx());

    ts.next_tx(@elixir);
    let mut management = ts.take_shared<LockedFundsManagement>();

    ts.next_tx(ALICE);
    {
        // Alice deposits 1000_000_000 BTC
        let btc_coin = coin::mint_for_testing<BTC>(1000_000_000, ts.ctx());
        locked_funds::deposit(&mut management, &global_config, btc_coin, ts.ctx());

        // Check Alice's collateral
        let btc_amount = locked_funds::get_user_collateral_amount<BTC>(&management, ALICE);
        let coin_types = locked_funds::get_user_collateral_coin_types(&management, ALICE);

        assert_eq(btc_amount, 1000_000_000);
        assert_eq(coin_types.length(), 1);
        assert!(coin_types.contains(&type_name::get<BTC>()), 0);

        // Alice deposits more 100_000_000 BTC
        let more_btc_coin = coin::mint_for_testing<BTC>(100_000_000, ts.ctx());
        locked_funds::deposit(&mut management, &global_config, more_btc_coin, ts.ctx());

        // Alice deposits 5000_000_000 ETH
        let btc_coin = coin::mint_for_testing<ETH>(5000_000_000, ts.ctx());
        locked_funds::deposit(&mut management, &global_config, btc_coin, ts.ctx());

        // Check updated collateral
        let updated_btc_amount = locked_funds::get_user_collateral_amount<BTC>(&management, ALICE);
        assert_eq(updated_btc_amount, 1100_000_000);
        let eth_coin = locked_funds::get_user_collateral_amount<ETH>(&management, ALICE);
        assert_eq(eth_coin, 5000_000_000);

        let updated_coin_types = locked_funds::get_user_collateral_coin_types(&management, ALICE);
        assert_eq(updated_coin_types.length(), 2);
        assert!(updated_coin_types.contains(&type_name::get<BTC>()), 0);
        assert!(updated_coin_types.contains(&type_name::get<ETH>()), 0);
    };

    ts.next_tx(BOB);
    {
        // Bob deposits 1000_000_000 ETH
        let btc_coin = coin::mint_for_testing<ETH>(1000_000_000, ts.ctx());
        locked_funds::deposit(&mut management, &global_config, btc_coin, ts.ctx());

        // Check Bob's collateral
        let bob_eth_amount = locked_funds::get_user_collateral_amount<ETH>(&management, BOB);
        let bob_coin_types = locked_funds::get_user_collateral_coin_types(&management, BOB);
        assert_eq(bob_eth_amount, 1000_000_000);
        assert_eq(bob_coin_types.length(), 1);
        assert!(bob_coin_types.contains(&type_name::get<ETH>()), 0);
    };

    config::destroy_for_test(global_config);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = locked_funds::EZeroAmount)]
fun test_deposit_if_collateral_amount_is_zero() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    locked_funds::init_for_test(ts.ctx());

    ts.next_tx(@elixir);
    let mut management = ts.take_shared<LockedFundsManagement>();

    ts.next_tx(ALICE);
    {
        let btc_coin = coin::zero<BTC>(ts.ctx());
        locked_funds::deposit(&mut management, &global_config, btc_coin, ts.ctx());
    };

    config::destroy_for_test(global_config);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_withdraw_success() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    locked_funds::init_for_test(ts.ctx());

    ts.next_tx(@elixir);
    let mut management = ts.take_shared<LockedFundsManagement>();

    ts.next_tx(ALICE);
    // Alice deposits 1000_000_000 BTC
    let btc_coin = coin::mint_for_testing<BTC>(1000_000_000, ts.ctx());
    locked_funds::deposit(&mut management, &global_config, btc_coin, ts.ctx());

    // Alice deposits 100_000_000 ETH
    let eth_coin = coin::mint_for_testing<ETH>(100_000_000, ts.ctx());
    locked_funds::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    // Alice withdraws 400_000_000 BTC
    locked_funds::withdraw<BTC>(&mut management, &global_config, 400_000_000, ts.ctx());

    ts.next_tx(ALICE);
    let withdrawn_btc = ts.take_from_sender<Coin<BTC>>();
    assert_eq(withdrawn_btc.value(), 400_000_000);
    withdrawn_btc.burn_for_testing();

    // Check Alice's remaining collateral
    let remaining_btc_amount = locked_funds::get_user_collateral_amount<BTC>(&management, ALICE);
    assert_eq(remaining_btc_amount, 600_000_000);

    let coin_types = locked_funds::get_user_collateral_coin_types(&management, ALICE);
    assert_eq(coin_types.length(), 2);
    assert!(coin_types.contains(&type_name::get<BTC>()), 0);
    assert!(coin_types.contains(&type_name::get<ETH>()), 0);

    // Alice withdraws all remaining BTC
    locked_funds::withdraw<BTC>(&mut management, &global_config, 600_000_000, ts.ctx());

    ts.next_tx(ALICE);
    let withdrawn_btc = ts.take_from_sender<Coin<BTC>>();
    assert_eq(withdrawn_btc.value(), 600_000_000);
    withdrawn_btc.burn_for_testing();

    // Check Alice's remaining collateral
    let remaining_btc_amount = locked_funds::get_user_collateral_amount<BTC>(&management, ALICE);
    assert_eq(remaining_btc_amount, 0);

    let coin_types = locked_funds::get_user_collateral_coin_types(&management, ALICE);
    assert_eq(coin_types.length(), 1);
    assert!(coin_types.contains(&type_name::get<ETH>()), 0);

    config::destroy_for_test(global_config);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure]
fun test_withdraw_if_collateral_amount_is_zero() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    locked_funds::init_for_test(ts.ctx());

    ts.next_tx(@elixir);
    let mut management = ts.take_shared<LockedFundsManagement>();

    ts.next_tx(ALICE);
    locked_funds::withdraw<BTC>(&mut management, &global_config, 0, ts.ctx());

    config::destroy_for_test(global_config);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = locked_funds::ENotEnoughAmount)]
fun test_withdraw_if_not_enough_amount() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    locked_funds::init_for_test(ts.ctx());

    ts.next_tx(@elixir);
    let mut management = ts.take_shared<LockedFundsManagement>();

    ts.next_tx(ALICE);
    let btc_coin = coin::mint_for_testing<BTC>(100_000_000, ts.ctx());
    locked_funds::deposit(&mut management, &global_config, btc_coin, ts.ctx());

    ts.next_tx(ALICE);
    locked_funds::withdraw<BTC>(&mut management, &global_config, 100_000_001, ts.ctx());

    config::destroy_for_test(global_config);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_withdraw_internal() {
    let mut ts = test_scenario::begin(@elixir);

    let global_config = config::create_for_test(ts.ctx());
    locked_funds::init_for_test(ts.ctx());

    ts.next_tx(@elixir);
    let mut management = ts.take_shared<LockedFundsManagement>();

    ts.next_tx(ALICE);
    let btc_coin = coin::mint_for_testing<BTC>(100_000_000, ts.ctx());
    locked_funds::deposit(&mut management, &global_config, btc_coin, ts.ctx());

    ts.next_tx(ALICE);
    let withdrawn_btc = locked_funds::withdraw_internal<BTC>(&mut management, ALICE, 100_000_000, ts.ctx());
    assert_eq(withdrawn_btc.value(), 100_000_000);
    withdrawn_btc.burn_for_testing();

    config::destroy_for_test(global_config);
    test_scenario::return_shared(management);
    ts.end();
}