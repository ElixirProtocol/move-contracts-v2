#[test_only]
module elixir::deusd_tests;

use elixir::deusd::{Self, DeUSDConfig, DEUSD, DeUSDTreasuryCap, DeUSDTreasuryCapConfig};
use sui::test_scenario;
use std::unit_test::assert_eq;
use elixir::admin_cap::AdminCap;
use elixir::config::GlobalConfig;
use elixir::config;
use elixir::test_utils;
use elixir::admin_cap;
use sui::coin::{Self, Coin, TreasuryCap, DenyCapV2};
use sui::test_scenario::Scenario;

const ADMIN: address = @0xad;
const BOB: address = @0xb0b;
const ALICE: address = @0xa11ce;

#[test]
fun test_mint_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, deusd_treasury_cap_config) = setup_test();

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

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAddress)]
fun test_mint_fail_if_to_zero_address() {
    let (mut ts, global_config, admin_cap, mut deusd_config, deusd_treasury_cap_config) = setup_test();

    {
        ts.next_tx(ADMIN);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, @0x0, amount, ts.ctx());
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAmount)]
fun test_mint_fail_if_zero_amount() {
    let (mut ts, global_config, admin_cap, mut deusd_config, deusd_treasury_cap_config) = setup_test();

    {
        ts.next_tx(ADMIN);
        deusd::mint(&mut deusd_config, BOB, 0, ts.ctx());
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
fun test_burn_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, deusd_treasury_cap_config) = setup_test();

    {
        ts.next_tx(ADMIN);
        let amount = 10_000_000_000_000;
        deusd::mint(&mut deusd_config, BOB, amount, ts.ctx());

        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());

        deusd::burn_from(&mut deusd_config, minted_coin, BOB);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
fun test_delete_deusd_config_success() {
    let (mut ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config) = setup_test();

    {
        ts.next_tx(ADMIN);
        deusd::delete_deusd_config(&admin_cap, deusd_config, &global_config, ALICE);
    };

    // Verify that the treasury cap still works after deleting the config
    {
        ts.next_tx(ADMIN);
        let mut treasury_cap = ts.take_from_address<TreasuryCap<DEUSD>>(ALICE);
        let amount = 10_000_000_000_000;
        coin::mint_and_transfer(&mut treasury_cap, amount, BOB, ts.ctx());

        ts.next_tx(ADMIN);
        let minted_coin = ts.take_from_address<Coin<DEUSD>>(BOB);
        assert_eq!(amount, minted_coin.value());

        test_scenario::return_to_address(ALICE, treasury_cap);
        coin::burn_for_testing(minted_coin);
    };

    test_scenario::return_shared(global_config);
    admin_cap::destroy_for_test(admin_cap);
    test_scenario::return_shared(deusd_treasury_cap_config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = config::EPackageVersionMismatch)]
fun test_delete_deusd_config_fail_if_package_version_mismatch() {
    let (mut ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config) = setup_test();

    {
        ts.next_tx(ADMIN);
        let mismatch_version_global_config = config::create_with_custom_version_for_test(0, ts.ctx());
        deusd::delete_deusd_config(&admin_cap, deusd_config, &mismatch_version_global_config, ALICE);
        config::destroy_for_test(mismatch_version_global_config);
    };

    test_scenario::return_shared(global_config);
    admin_cap::destroy_for_test(admin_cap);
    test_scenario::return_shared(deusd_treasury_cap_config);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAddress)]
fun test_delete_deusd_config_fail_if_caps_owner_zero_address() {
    let (mut ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config) = setup_test();

    {
        ts.next_tx(ADMIN);
        deusd::delete_deusd_config(&admin_cap, deusd_config, &global_config, @0x0);
    };

    test_scenario::return_shared(global_config);
    admin_cap::destroy_for_test(admin_cap);
    test_scenario::return_shared(deusd_treasury_cap_config);
    ts.end();
}

#[test]
fun test_initialize_deusd_config_success() {
    let (mut ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config) = setup_test();

    // Delete the config
    {
        ts.next_tx(ADMIN);
        deusd::delete_deusd_config(&admin_cap, deusd_config, &global_config, ALICE);
    };

    // Initialize a new DeUSD config
    {
        ts.next_tx(ADMIN);

        let treasury_cap = ts.take_from_address<TreasuryCap<DEUSD>>(ALICE);
        let deny_cap = ts.take_from_address<DenyCapV2<DEUSD>>(ALICE);

        ts.next_tx(ALICE);
        deusd::initialize_deusd_config(&global_config, treasury_cap, deny_cap, ts.ctx());
    };

    ts.next_tx(ALICE);
    let mut deusd_config = ts.take_shared<DeUSDConfig>();

    // Test mint to ensure the new config is working
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

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
fun test_create_deusd_treasury_cap_success() {
    let (mut ts, global_config, admin_cap, deusd_config, mut deusd_treasury_cap_config) = setup_test();

    // Create the treasury cap for BOB
    {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, BOB, ts.ctx());

        ts.next_tx(ADMIN);
        let treasury_cap = ts.take_from_address<DeUSDTreasuryCap>(BOB);
        assert!(deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));

        test_scenario::return_to_address(BOB, treasury_cap);
    };

    // Create the treasury cap for ALICE
    {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, ALICE, ts.ctx());

        ts.next_tx(ADMIN);
        let treasury_cap = ts.take_from_address<DeUSDTreasuryCap>(ALICE);
        assert!(deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));

        test_scenario::return_to_address(ALICE, treasury_cap);
    };

    let treasury_caps = deusd::get_treasury_caps(&deusd_treasury_cap_config);
    let len = treasury_caps.length();
    let mut i = 0;
    while (i < len) {
        let cap_view = treasury_caps[i];
        let (cap_id, is_active) = deusd::extract_treasury_cap_view_for_test(cap_view);
        assert_eq!(deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, cap_id), is_active);
        i = i + 1;
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
#[expected_failure(abort_code = config::EPackageVersionMismatch)]
fun test_create_deusd_treasury_cap_fail_if_package_version_mismatch() {
    let (mut ts, global_config, admin_cap, deusd_config, mut deusd_treasury_cap_config) = setup_test();

    {
        ts.next_tx(ADMIN);
        let mismatch_version_global_config = config::create_with_custom_version_for_test(0, ts.ctx());
        deusd::create_treasury_cap(
            &admin_cap,
            &mut deusd_treasury_cap_config,
            &mismatch_version_global_config,
            BOB,
            ts.ctx()
        );
        config::destroy_for_test(mismatch_version_global_config);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAddress)]
fun test_create_deusd_treasury_cap_fail_if_to_zero_address() {
    let (mut ts, global_config, admin_cap, deusd_config, mut deusd_treasury_cap_config) = setup_test();

    {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, @0x0, ts.ctx());
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
fun test_set_deusd_treasury_cap_status_success() {
    let (mut ts, global_config, admin_cap, deusd_config, mut deusd_treasury_cap_config) = setup_test();

    // Create the treasury cap
    let treasury_cap = {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, BOB, ts.ctx());

        ts.next_tx(ADMIN);
        ts.take_from_address<DeUSDTreasuryCap>(BOB)
    };

    // Deactivate the treasury cap
    {
        ts.next_tx(ADMIN);
        deusd::set_treasury_cap_status(
            &admin_cap,
            &mut deusd_treasury_cap_config,
            &global_config,
            object::id(&treasury_cap),
            false
        );
        assert!(!deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));
    };

    // Should do nothing if setting to the same status
    {
        ts.next_tx(ADMIN);
        deusd::set_treasury_cap_status(
            &admin_cap,
            &mut deusd_treasury_cap_config,
            &global_config,
            object::id(&treasury_cap),
            false
        );
        assert!(!deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));
    };

    // Reactivate the treasury cap
    {
        ts.next_tx(ADMIN);
        deusd::set_treasury_cap_status(
            &admin_cap,
            &mut deusd_treasury_cap_config,
            &global_config,
            object::id(&treasury_cap),
            true
        );
        assert!(deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));
    };

    // Should do nothing if setting to the same status
    {
        ts.next_tx(ADMIN);
        deusd::set_treasury_cap_status(
            &admin_cap,
            &mut deusd_treasury_cap_config,
            &global_config,
            object::id(&treasury_cap),
            true
        );
        assert!(deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));
    };

    test_scenario::return_to_address(BOB, treasury_cap);
    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
#[expected_failure(abort_code = deusd::ENotDeUSDTreasuryCapID)]
fun test_set_deusd_treasury_cap_status_fail_if_not_exist() {
    let (mut ts, global_config, admin_cap, deusd_config, mut deusd_treasury_cap_config) = setup_test();

    {
        ts.next_tx(ADMIN);
        let not_a_cap_id = object::id_from_address(@0x12356);
        deusd::set_treasury_cap_status(&admin_cap, &mut deusd_treasury_cap_config, &global_config, not_a_cap_id, false);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
fun test_mint_with_cap_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut deusd_treasury_cap_config) = setup_test();

    // Create the treasury cap
    {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, BOB, ts.ctx());
    };

    // Mint using the treasury cap
    {
        ts.next_tx(ADMIN);
        let treasury_cap = ts.take_from_address<DeUSDTreasuryCap>(BOB);
        assert!(deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));

        ts.next_tx(BOB);
        let amount = 5_000_000_000_000;
        deusd::mint_with_cap(
            &treasury_cap,
            &mut deusd_config,
            &deusd_treasury_cap_config,
            &global_config,
            BOB,
            amount,
            ts.ctx()
        );

        assert_eq!(deusd::total_supply(&deusd_config), amount);

        // Check that BOB received the coin
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());

        coin::burn_for_testing(minted_coin);

        test_scenario::return_to_address(BOB, treasury_cap);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
#[expected_failure(abort_code = deusd::EDeUSDTreasuryCapNotActive)]
fun test_mint_with_cap_fail_if_cap_not_active() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut deusd_treasury_cap_config) = setup_test();

    // Create the treasury cap
    let treasury_cap = {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, BOB, ts.ctx());

        ts.next_tx(ADMIN);
        ts.take_from_address<DeUSDTreasuryCap>(BOB)
    };

    // Deactivate the treasury cap
    {
        ts.next_tx(ADMIN);
        deusd::set_treasury_cap_status(
            &admin_cap,
            &mut deusd_treasury_cap_config,
            &global_config,
            object::id(&treasury_cap),
            false
        );
        assert!(!deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));
    };

    // Try to mint using the deactivated treasury cap
    {
        ts.next_tx(BOB);
        let amount = 5_000_000_000_000;
        deusd::mint_with_cap(
            &treasury_cap,
            &mut deusd_config,
            &deusd_treasury_cap_config,
            &global_config,
            BOB,
            amount,
            ts.ctx()
        );

        test_scenario::return_to_address(BOB, treasury_cap);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAddress)]
fun test_mint_with_cap_fail_if_to_zero_address() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut deusd_treasury_cap_config) = setup_test();

    // Create the treasury cap
    {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, BOB, ts.ctx());
    };

    // Mint using the treasury cap
    {
        ts.next_tx(ADMIN);
        let treasury_cap = ts.take_from_address<DeUSDTreasuryCap>(BOB);
        assert!(deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));

        ts.next_tx(BOB);
        let amount = 5_000_000_000_000;
        deusd::mint_with_cap(
            &treasury_cap,
            &mut deusd_config,
            &deusd_treasury_cap_config,
            &global_config,
            @0x0,
            amount,
            ts.ctx()
        );

        test_scenario::return_to_address(BOB, treasury_cap);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
#[expected_failure(abort_code = deusd::EZeroAmount)]
fun test_mint_with_cap_fail_if_zero_amount() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut deusd_treasury_cap_config) = setup_test();

    // Create the treasury cap
    {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, BOB, ts.ctx());
    };

    // Mint using the treasury cap
    {
        ts.next_tx(ADMIN);
        let treasury_cap = ts.take_from_address<DeUSDTreasuryCap>(BOB);
        assert!(deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));

        ts.next_tx(BOB);
        deusd::mint_with_cap(
            &treasury_cap,
            &mut deusd_config,
            &deusd_treasury_cap_config,
            &global_config,
            BOB,
            0,
            ts.ctx()
        );

        test_scenario::return_to_address(BOB, treasury_cap);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
fun test_burn_with_cap_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut deusd_treasury_cap_config) = setup_test();

    // Create the treasury cap
    {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, BOB, ts.ctx());
    };

    // Mint and burn using the treasury cap
    {
        ts.next_tx(ADMIN);
        let treasury_cap = ts.take_from_address<DeUSDTreasuryCap>(BOB);
        assert!(deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));

        ts.next_tx(BOB);
        let amount = 5_000_000_000_000;
        deusd::mint_with_cap(
            &treasury_cap,
            &mut deusd_config,
            &deusd_treasury_cap_config,
            &global_config,
            BOB,
            amount,
            ts.ctx()
        );

        // Check that BOB received the coin
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());

        // Burn using the treasury cap
        deusd::burn_with_cap(
            &treasury_cap,
            &mut deusd_config,
            &deusd_treasury_cap_config,
            &global_config,
            minted_coin,
            BOB
        );

        // Check that the total supply is now zero
        assert_eq!(deusd::total_supply(&deusd_config), 0);

        test_scenario::return_to_address(BOB, treasury_cap);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

#[test]
#[expected_failure(abort_code = deusd::EDeUSDTreasuryCapNotActive)]
fun test_burn_with_cap_fail_if_cap_not_active() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut deusd_treasury_cap_config) = setup_test();

    // Create the treasury cap
    let treasury_cap = {
        ts.next_tx(ADMIN);
        deusd::create_treasury_cap(&admin_cap, &mut deusd_treasury_cap_config, &global_config, BOB, ts.ctx());

        ts.next_tx(ADMIN);
        ts.take_from_address<DeUSDTreasuryCap>(BOB)
    };

    // Deactivate the treasury cap
    {
        ts.next_tx(ADMIN);
        deusd::set_treasury_cap_status(
            &admin_cap,
            &mut deusd_treasury_cap_config,
            &global_config,
            object::id(&treasury_cap),
            false
        );
        assert!(!deusd::is_active_deusd_treasury_cap(&deusd_treasury_cap_config, object::id(&treasury_cap)));
    };

    // Mint using another active cap (the admin cap)
    let minted_coin = {
        ts.next_tx(ADMIN);
        let amount = 5_000_000_000_000;
        deusd::mint(&mut deusd_config, BOB, amount, ts.ctx());

        // Check that BOB received the coin
        ts.next_tx(BOB);
        let minted_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq!(amount, minted_coin.value());
        minted_coin
    };

    // Try to burn using the deactivated treasury cap
    {
        ts.next_tx(BOB);
        deusd::burn_with_cap(
            &treasury_cap,
            &mut deusd_config,
            &deusd_treasury_cap_config,
            &global_config,
            minted_coin,
            BOB
        );

        test_scenario::return_to_address(BOB, treasury_cap);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config);
}

// === Helper Functions ===

public fun setup_test(): (Scenario, GlobalConfig, AdminCap, DeUSDConfig, DeUSDTreasuryCapConfig) {
    let mut ts = test_scenario::begin(ADMIN);

    let (global_config, admin_cap) = test_utils::setup_global_config(&mut ts, ADMIN);
    let deusd_config = test_utils::setup_deusd(&mut ts, ADMIN);
    let deusd_treasury_cap_config = test_utils::setup_deusd_treasury_cap_config(
        &mut ts,
        &admin_cap,
        &global_config,
        ADMIN
    );

    (ts, global_config, admin_cap, deusd_config, deusd_treasury_cap_config)
}

public fun clean_test(
    ts: Scenario,
    global_config: GlobalConfig,
    admin_cap: AdminCap,
    deusd_config: DeUSDConfig,
    deusd_treasury_cap_config: DeUSDTreasuryCapConfig,
) {
    test_scenario::return_shared(global_config);
    admin_cap::destroy_for_test(admin_cap);
    test_scenario::return_shared(deusd_config);
    test_scenario::return_shared(deusd_treasury_cap_config);
    ts.end();
}