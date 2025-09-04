#[test_only]
module elixir::wdeusd_vault_tests;

// === Imports ===

use sui::test_scenario::{Self as ts, Scenario};
use sui::coin::{Self, Coin};
use elixir::admin_cap::AdminCap;
use elixir::wdeusd_vault::{Self, WDEUSDVault};
use elixir::deusd::{DEUSD, DeUSDConfig};
use elixir::test_utils;

// === Test Structs ===

public struct TestWDEUSD has drop {}

// === Constants ===

const ADMIN: address = @0xad;
const USER1: address = @0xb1;
const USER2: address = @0xc1;

// === Tests ===

#[test]
fun test_initialize_vault() {
    let (mut scenario, deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        // Initialize the vault
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        // Verify vault was created and shared
        let vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);

        // Vault should be unpaused by default
        assert!(!wdeusd_vault::is_paused(&vault), 0);

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
fun test_pause_vault_success() {
    let (mut scenario, deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);

        // Pause the vault
        wdeusd_vault::pause(&admin_cap, &mut vault);

        // Verify vault is paused
        assert!(wdeusd_vault::is_paused(&vault), 0);

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = wdeusd_vault::EVaultPaused)]
fun test_pause_already_paused_vault() {
    let (mut scenario, deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);

        wdeusd_vault::pause(&admin_cap, &mut vault);
        assert!(wdeusd_vault::is_paused(&vault), 0);

        // Attempt to pause again - should fail
        wdeusd_vault::pause(&admin_cap, &mut vault);

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
fun test_unpause_vault_success() {
    let (mut scenario, deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);

        wdeusd_vault::pause(&admin_cap, &mut vault);
        assert!(wdeusd_vault::is_paused(&vault), 0);

        // Then unpause it
        wdeusd_vault::unpause(&admin_cap, &mut vault);
        assert!(!wdeusd_vault::is_paused(&vault), 1);

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = wdeusd_vault::EVaultNotPaused)]
fun test_unpause_not_paused_vault() {
    let (mut scenario, deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);

        // Attempt to unpause when not paused - should fail
        wdeusd_vault::unpause(&admin_cap, &mut vault);

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
fun test_claim_deusd_success() {
    let (mut scenario, mut deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);

        let wdeusd_coin = mint_test_wdeusd(1000, scenario.ctx());

        wdeusd_vault::claim_deusd(
            &mut vault,
            &mut deusd_config,
            wdeusd_coin,
            USER2,
            scenario.ctx()
        );

        // Verify vault balance increased
        assert!(wdeusd_vault::balance(&vault) == 1000, 0);

        ts::return_shared(vault);
    };

    scenario.next_tx(USER2);
    {
        // Verify USER2 received deUSD
        let deusd_coin = ts::take_from_address<Coin<DEUSD>>(&scenario, USER2);
        assert!(deusd_coin.value() == 1000, 1);
        coin::burn_for_testing(deusd_coin);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}


#[test]
#[expected_failure(abort_code = wdeusd_vault::EVaultPaused)]
fun test_claim_deusd_when_paused() {
    let (mut scenario, mut deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        wdeusd_vault::pause(&admin_cap, &mut vault);
        ts::return_shared(vault);
    };

    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let wdeusd_coin = mint_test_wdeusd(1000, scenario.ctx());

        // This should fail because vault is paused
        wdeusd_vault::claim_deusd(
            &mut vault,
            &mut deusd_config,
            wdeusd_coin,
            USER2,
            scenario.ctx()
        );

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = wdeusd_vault::EInvalidAmount)]
fun test_claim_deusd_zero_amount() {
    let (mut scenario, mut deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let wdeusd_coin = mint_test_wdeusd(0, scenario.ctx());

        // This should fail because amount is zero
        wdeusd_vault::claim_deusd(
            &mut vault,
            &mut deusd_config,
            wdeusd_coin,
            USER2,
            scenario.ctx()
        );

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
fun test_return_deusd_success() {
    let (mut scenario, mut deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    // Add some WDEUSD to the vault
    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let wdeusd_coin = mint_test_wdeusd(2000, scenario.ctx());

        wdeusd_vault::claim_deusd(
            &mut vault,
            &mut deusd_config,
            wdeusd_coin,
            USER1,
            scenario.ctx()
        );

        ts::return_shared(vault);
    };

    // Return some deUSD
    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let mut deusd_coin = ts::take_from_address<Coin<DEUSD>>(&scenario, USER1);

        // Return half of the deUSD
        let return_amount = 1000;
        let return_coin = deusd_coin.split(return_amount, scenario.ctx());

        wdeusd_vault::return_deusd(
            &mut vault,
            &mut deusd_config,
            return_coin,
            USER2,
            scenario.ctx()
        );

        // Verify vault balance decreased
        assert!(wdeusd_vault::balance(&vault) == 1000, 0);

        ts::return_shared(vault);
        coin::burn_for_testing(deusd_coin);
    };

    scenario.next_tx(USER2);
    {
        // Verify USER2 received WDEUSD
        let wdeusd_coin = ts::take_from_address<Coin<TestWDEUSD>>(&scenario, USER2);
        assert!(wdeusd_coin.value() == 1000, 1);
        coin::burn_for_testing(wdeusd_coin);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = wdeusd_vault::EVaultPaused)]
fun test_return_deusd_when_paused() {
    let (mut scenario, mut deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    scenario.next_tx(ADMIN);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        wdeusd_vault::pause(&admin_cap, &mut vault);
        ts::return_shared(vault);
    };

    // Add some WDEUSD to the vault
    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let wdeusd_coin = mint_test_wdeusd(2000, scenario.ctx());

        wdeusd_vault::claim_deusd(
            &mut vault,
            &mut deusd_config,
            wdeusd_coin,
            USER1,
            scenario.ctx()
        );

        ts::return_shared(vault);
    };

    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let deusd_coin = mint_deusd(1000, scenario.ctx());

        // This should fail because vault is paused
        wdeusd_vault::return_deusd(
            &mut vault,
            &mut deusd_config,
            deusd_coin,
            USER2,
            scenario.ctx()
        );

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = wdeusd_vault::EInvalidAmount)]
fun test_return_deusd_zero_amount() {
    let (mut scenario, mut deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    // Add some WDEUSD to the vault
    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let wdeusd_coin = mint_test_wdeusd(2000, scenario.ctx());

        wdeusd_vault::claim_deusd(
            &mut vault,
            &mut deusd_config,
            wdeusd_coin,
            USER1,
            scenario.ctx()
        );

        ts::return_shared(vault);
    };

    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let deusd_coin = mint_deusd(0, scenario.ctx());

        // This should fail because amount is zero
        wdeusd_vault::return_deusd(
            &mut vault,
            &mut deusd_config,
            deusd_coin,
            USER2,
            scenario.ctx()
        );

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = wdeusd_vault::EInsufficientFunds)]
fun test_return_deusd_insufficient_funds() {
    let (mut scenario, mut deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    // Add some WDEUSD to the vault
    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let wdeusd_coin = mint_test_wdeusd(2000, scenario.ctx());

        wdeusd_vault::claim_deusd(
            &mut vault,
            &mut deusd_config,
            wdeusd_coin,
            USER1,
            scenario.ctx()
        );

        ts::return_shared(vault);
    };

    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let deusd_coin = mint_deusd(2001, scenario.ctx());

        // This should fail because vault does not have enough WDEUSD balance
        wdeusd_vault::return_deusd(
            &mut vault,
            &mut deusd_config,
            deusd_coin,
            USER2,
            scenario.ctx()
        );

        ts::return_shared(vault);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

#[test]
fun test_multiple_claims_and_returns() {
    let (mut scenario, mut deusd_config, admin_cap) = setup_test();

    scenario.next_tx(ADMIN);
    {
        wdeusd_vault::initialize<TestWDEUSD>(&admin_cap, scenario.ctx());
    };

    // First claim
    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let wdeusd_coin = mint_test_wdeusd(1000, scenario.ctx());

        wdeusd_vault::claim_deusd(
            &mut vault,
            &mut deusd_config,
            wdeusd_coin,
            USER1,
            scenario.ctx()
        );

        assert!(wdeusd_vault::balance(&vault) == 1000, 0);
        ts::return_shared(vault);
    };

    // Second claim by different user
    scenario.next_tx(USER2);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let wdeusd_coin = mint_test_wdeusd(500, scenario.ctx());

        wdeusd_vault::claim_deusd(
            &mut vault,
            &mut deusd_config,
            wdeusd_coin,
            USER2,
            scenario.ctx()
        );

        assert!(wdeusd_vault::balance(&vault) == 1500, 1);
        ts::return_shared(vault);
    };

    // Partial return by USER1
    scenario.next_tx(USER1);
    {
        let mut vault = ts::take_shared<WDEUSDVault<TestWDEUSD>>(&scenario);
        let mut deusd_coin = ts::take_from_address<Coin<DEUSD>>(&scenario, USER1);
        let return_coin = deusd_coin.split(300, scenario.ctx());

        wdeusd_vault::return_deusd(
            &mut vault,
            &mut deusd_config,
            return_coin,
            USER1,
            scenario.ctx()
        );

        assert!(wdeusd_vault::balance(&vault) == 1200, 2);
        ts::return_shared(vault);
        coin::burn_for_testing(deusd_coin);
    };

    ts::return_shared(deusd_config);
    sui::test_utils::destroy(admin_cap);
    scenario.end();
}

// === Helper Functions ===

fun setup_test(): (Scenario, DeUSDConfig, AdminCap) {
    let mut scenario = ts::begin(ADMIN);

    let deusd_config = test_utils::setup_deusd(&mut scenario, ADMIN);

    let (global_config, admin_cap) = test_utils::setup_global_config(&mut scenario, ADMIN);
    ts::return_shared(global_config);

    (scenario, deusd_config, admin_cap)
}

fun mint_test_wdeusd(amount: u64, ctx: &mut TxContext): Coin<TestWDEUSD> {
    coin::mint_for_testing<TestWDEUSD>(amount, ctx)
}

fun mint_deusd(amount: u64, ctx: &mut TxContext): Coin<DEUSD> {
    coin::mint_for_testing<DEUSD>(amount, ctx)
}