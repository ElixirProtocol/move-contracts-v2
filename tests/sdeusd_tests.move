#[test_only]
module elixir::sdeusd_tests;

use elixir::sdeusd::{Self, StdeUSDManagement, UserCooldowns, UserBalances};
use elixir::deusd_silo::DeUSDSilo;
use elixir::deusd::{Self, DEUSD, DeUSDConfig};
use elixir::config::{Self, GlobalConfig};
use elixir::admin_cap::{Self, AdminCap};
use elixir::roles;
use sui::test_scenario;
use sui::clock;
use sui::coin;

/// 1000 tokens with 6 decimals (same as deUSD)
const TOKEN_1000: u64 = 1000_000_000;
/// 500 tokens with 6 decimals
const TOKEN_500: u64 = 500_000_000;
/// 100 tokens with 6 decimals
const TOKEN_100: u64 = 100_000_000;
/// 50 tokens with 6 decimals
const TOKEN_50: u64 = 50_000_000;
/// 550 tokens with 6 decimals
const TOKEN_550: u64 = 550_000_000;
/// 10 tokens with 6 decimals
const TOKEN_10: u64 = 10_000_000;
/// 1 token with 6 decimals
const TOKEN_1: u64 = 1_000_000;
/// Minimum shares amount
const MIN_SHARES: u64 = 1_000_000;

const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;
const CHARLIE: address = @0xc0ffee;
const ADMIN: address = @0xad;
const DAVE: address = @0xdae;
const EVE: address = @0xee;

// === Test Setup Helper Functions ===

fun setup_global_config(ts: &mut test_scenario::Scenario): (GlobalConfig, AdminCap) {
    config::init_for_test(ts.ctx());
    admin_cap::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let global_config = ts.take_shared<GlobalConfig>();
    let admin_cap = ts.take_from_sender<AdminCap>();
    
    (global_config, admin_cap)
}

fun setup_deusd(ts: &mut test_scenario::Scenario): DeUSDConfig {
    deusd::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    ts.take_shared<DeUSDConfig>()
}

fun setup_complete(): (test_scenario::Scenario, GlobalConfig, AdminCap, DeUSDConfig) {
    let mut ts = test_scenario::begin(ADMIN);
    let (global_config, admin_cap) = setup_global_config(&mut ts);
    let deusd_config = setup_deusd(&mut ts);
    
    // Initialize sdeusd
    sdeusd::init_for_test(ts.ctx());
    
    (ts, global_config, admin_cap, deusd_config)
}

fun mint_deusd(deusd_config: &mut DeUSDConfig, _to: address, amount: u64, ts: &mut test_scenario::Scenario): coin::Coin<DEUSD> {
    deusd::mint_for_test(deusd_config, ADMIN, amount, ts.ctx())
}

// === Initialization Tests ===

#[test]
fun test_initialization() {
    let (mut ts, global_config, admin_cap, deusd_config) = setup_complete();
    let clock = clock::create_for_testing(ts.ctx());
    
    ts.next_tx(ADMIN);
    let management = ts.take_shared<StdeUSDManagement>();
    let user_cooldowns = ts.take_shared<UserCooldowns>();
    let user_balances = ts.take_shared<UserBalances>();
    let silo = ts.take_shared<DeUSDSilo>();
    
    // Test that initial state is correct
    assert!(sdeusd::get_unvested_amount(&management, &clock) == 0, 0);
    assert!(sdeusd::total_supply(&management) == 0, 1);
    assert!(sdeusd::cooldown_duration(&management) == 90 * 86400 * 1000, 2); // 90 days
    assert!(sdeusd::total_assets(&management, &clock) == 0, 3);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_cooldowns);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(silo);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Role Management Tests ===

#[test]
fun test_role_management() {
    let (mut ts, mut global_config, admin_cap, deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    
    // Grant rewarder role to ALICE
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_rewarder());
    
    // Grant blacklist manager role to BOB
    config::add_role(&admin_cap, &mut global_config, BOB, roles::role_blacklist_manager());
    
    // Verify roles were granted
    assert!(global_config.has_role(ALICE, roles::role_rewarder()), 0);
    assert!(global_config.has_role(BOB, roles::role_blacklist_manager()), 1);
    
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    ts.end();
}

// === Blacklist Management Tests ===

#[test]
fun test_blacklist_management() {
    let (mut ts, mut global_config, admin_cap, deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Grant blacklist manager role to admin
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    
    // Add ALICE to soft blacklist
    sdeusd::add_to_blacklist(&mut management, &global_config, ALICE, false, ts.ctx());
    
    // Add BOB to full blacklist
    sdeusd::add_to_blacklist(&mut management, &global_config, BOB, true, ts.ctx());
    
    // Verify blacklist status
    assert!(sdeusd::is_soft_restricted(&management, ALICE), 0);
    assert!(sdeusd::is_full_restricted(&management, BOB), 1);
    
    // Remove from blacklists
    sdeusd::remove_from_blacklist(&mut management, &global_config, ALICE, false, ts.ctx());
    sdeusd::remove_from_blacklist(&mut management, &global_config, BOB, true, ts.ctx());
    
    // Verify removal
    assert!(!sdeusd::is_soft_restricted(&management, ALICE), 2);
    assert!(!sdeusd::is_full_restricted(&management, BOB), 3);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::ENotAuthorized)]
fun test_blacklist_unauthorized_fails() {
    let (mut ts, global_config, admin_cap, deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Try to blacklist without proper role
    sdeusd::add_to_blacklist(&mut management, &global_config, BOB, false, ts.ctx());
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    ts.end();
}

// === Cooldown Duration Tests ===

#[test]
fun test_cooldown_duration_setting() {
    let (mut ts, global_config, admin_cap, deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Set cooldown duration to 7 days
    let new_duration = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, new_duration, ts.ctx());
    
    // Verify the duration was set
    assert!(sdeusd::cooldown_duration(&management) == new_duration, 0);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EInvalidCooldown)]
fun test_cooldown_duration_too_long_fails() {
    let (mut ts, global_config, admin_cap, deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Try to set cooldown duration longer than maximum (90 days)
    let invalid_duration = 91 * 24 * 60 * 60 * 1000; // 91 days
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, invalid_duration, ts.ctx());
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    ts.end();
}

// === Deposit Tests ===

#[test]
fun test_deposit_success() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Mint some deUSD for ALICE
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    
    // Deposit deUSD tokens
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    // Check that shares were received (1:1 ratio initially)
    assert!(coin::value(&shares_coin) == TOKEN_1000, 0);
    assert!(sdeusd::get_user_balance_info(&user_balances, ALICE) == TOKEN_1000, 1);
    assert!(sdeusd::total_supply(&management) == TOKEN_1000, 2);
    
    coin::burn_for_testing(shares_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_deposit_zero_amount_fails() {
    let (mut ts, global_config, admin_cap, deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Try to deposit zero amount
    let zero_coin = coin::zero<DEUSD>(ts.ctx());
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        zero_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    coin::burn_for_testing(shares_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_deposit_soft_restricted_caller_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Grant blacklist manager role and blacklist ALICE
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(&mut management, &global_config, ALICE, false, ts.ctx()); // soft restriction
    
    ts.next_tx(ALICE);
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Mint deUSD for restricted user
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    
    // Try to deposit as soft restricted user
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    coin::burn_for_testing(shares_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Rewards Tests ===

#[test]
fun test_transfer_in_rewards_success() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Grant rewarder role to ALICE
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_rewarder());
    
    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());
    
    // Mint rewards
    let rewards_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_100, &mut ts);
    
    // Transfer rewards
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );
    
    // Check that rewards were added to balance but are still vesting
    assert!(sdeusd::get_unvested_amount(&management, &clock) == TOKEN_100, 0);
    assert!(sdeusd::total_assets(&management, &clock) == 0, 1); // Should be 0 since all rewards are vesting
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::ENotAuthorized)]
fun test_transfer_in_rewards_unauthorized_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Mint rewards
    let rewards_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_100, &mut ts);
    
    // Try to transfer rewards without rewarder role
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_transfer_in_rewards_zero_amount_fails() {
    let (mut ts, mut global_config, admin_cap, deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());
    
    let clock = clock::create_for_testing(ts.ctx());
    
    // Try to transfer zero rewards
    let zero_coin = coin::zero<DEUSD>(ts.ctx());
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        zero_coin,
        &clock,
        ts.ctx()
    );
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Vesting Tests ===

#[test]
fun test_vesting_mechanism() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());
    
    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000; // Some timestamp
    clock::set_for_testing(&mut clock, start_time);
    
    // Transfer rewards
    let rewards_coin = mint_deusd(&mut deusd_config, ADMIN, TOKEN_100, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );
    
    // Initially all rewards are unvested
    assert!(sdeusd::get_unvested_amount(&management, &clock) == TOKEN_100, 0);
    assert!(sdeusd::total_assets(&management, &clock) == 0, 1);
    
    // After 4 hours (half vesting period), half should be vested
    let half_vesting_time = start_time + (4 * 3600 * 1000); // 4 hours
    clock::set_for_testing(&mut clock, half_vesting_time);
    
    let unvested_half = sdeusd::get_unvested_amount(&management, &clock);
    let total_assets_half = sdeusd::total_assets(&management, &clock);
    
    // Should be approximately 50 tokens unvested and 50 available
    assert!(unvested_half == TOKEN_50, 2);
    assert!(total_assets_half == TOKEN_50, 3);
    
    // After full vesting period (8 hours), all should be vested
    let full_vesting_time = start_time + (8 * 3600 * 1000); // 8 hours
    clock::set_for_testing(&mut clock, full_vesting_time);
    
    assert!(sdeusd::get_unvested_amount(&management, &clock) == 0, 4);
    assert!(sdeusd::total_assets(&management, &clock) == TOKEN_100, 5);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Cooldown Tests ===

#[test]
fun test_cooldown_assets_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let mut user_cooldowns = ts.take_shared<UserCooldowns>();
    let mut silo = ts.take_shared<DeUSDSilo>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit to get shares
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Start cooldown for 500 assets
    let assets_to_cooldown = TOKEN_500;
    let shares_returned = sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        &mut user_cooldowns,
        &mut user_balances,
        &mut silo,
        assets_to_cooldown,
        &clock,
        ts.ctx()
    );
    
    // Check that shares were burned and cooldown was set
    assert!(shares_returned == assets_to_cooldown, 0); // 1:1 ratio
    assert!(sdeusd::get_user_balance_info(&user_balances, ALICE) == TOKEN_500, 1); // Remaining balance
    
    let cooldown_info = sdeusd::get_user_cooldown_info(&user_cooldowns, ALICE);
    assert!(sdeusd::cooldown_underlying_amount(&cooldown_info) == assets_to_cooldown, 2);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(user_cooldowns);
    test_scenario::return_shared(silo);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_cooldown_assets_zero_cooldown_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Set cooldown duration to zero
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0, ts.ctx());
    
    ts.next_tx(ALICE);
    let mut user_balances = ts.take_shared<UserBalances>();
    let mut user_cooldowns = ts.take_shared<UserCooldowns>();
    let mut silo = ts.take_shared<DeUSDSilo>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Try to start cooldown when cooldown duration is zero
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        &mut user_cooldowns,
        &mut user_balances,
        &mut silo,
        TOKEN_500,
        &clock,
        ts.ctx()
    );
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(user_cooldowns);
    test_scenario::return_shared(silo);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Unstake Tests ===

#[test]
fun test_unstake_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let mut user_cooldowns = ts.take_shared<UserCooldowns>();
    let mut silo = ts.take_shared<DeUSDSilo>();
    let mut clock = clock::create_for_testing(ts.ctx());
    
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Start cooldown
    let assets_to_cooldown = TOKEN_500;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        &mut user_cooldowns,
        &mut user_balances,
        &mut silo,
        assets_to_cooldown,
        &clock,
        ts.ctx()
    );
    
    // Advance time past cooldown period
    let current_time = clock::timestamp_ms(&clock);
    let cooldown_duration = sdeusd::cooldown_duration(&management);
    clock::set_for_testing(&mut clock, current_time + cooldown_duration + 1);
    
    // Unstake
    let unstaked_coin = sdeusd::unstake(
        &management,
        &global_config,
        &mut user_cooldowns,
        &mut silo,
        BOB, // Receive at different address
        &clock,
        ts.ctx()
    );
    
    // Check that assets were received
    assert!(coin::value(&unstaked_coin) == assets_to_cooldown, 0);
    
    // Check that cooldown was cleared
    let cooldown_info = sdeusd::get_user_cooldown_info(&user_cooldowns, ALICE);
    assert!(sdeusd::cooldown_underlying_amount(&cooldown_info) == 0, 1);
    
    coin::burn_for_testing(unstaked_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(user_cooldowns);
    test_scenario::return_shared(silo);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EInvalidCooldown)]
fun test_unstake_before_cooldown_end_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let mut user_cooldowns = ts.take_shared<UserCooldowns>();
    let mut silo = ts.take_shared<DeUSDSilo>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit and start cooldown
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        &mut user_cooldowns,
        &mut user_balances,
        &mut silo,
        TOKEN_500,
        &clock,
        ts.ctx()
    );
    
    // Try to unstake immediately (before cooldown ends)
    let unstaked_coin = sdeusd::unstake(
        &management,
        &global_config,
        &mut user_cooldowns,
        &mut silo,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    coin::burn_for_testing(unstaked_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(user_cooldowns);
    test_scenario::return_shared(silo);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Preview Function Tests ===

#[test]
fun test_preview_functions() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Test with empty vault (1:1 ratio)
    let assets = TOKEN_1000;
    let expected_shares = sdeusd::preview_deposit(&management, assets, &clock);
    assert!(expected_shares == assets, 0);
    
    let expected_assets = sdeusd::preview_mint(&management, assets, &clock);
    assert!(expected_assets == assets, 1);
    
    // Make a deposit to change the ratio
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, assets, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Test preview functions with existing deposits
    let new_assets = TOKEN_500;
    let new_shares = sdeusd::preview_deposit(&management, new_assets, &clock);
    
    // Should still be 1:1 since no rewards have been added
    assert!(new_shares == new_assets, 2);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Integration Test ===

#[test]
fun test_full_staking_flow() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let mut user_cooldowns = ts.take_shared<UserCooldowns>();
    let mut silo = ts.take_shared<DeUSDSilo>();
    
    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());
    
    ts.next_tx(ALICE);
    let mut clock = clock::create_for_testing(ts.ctx());
    
    // 1. Alice deposits 1000 deUSD
    let initial_deposit = TOKEN_1000;
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, initial_deposit, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    assert!(coin::value(&shares_coin) == initial_deposit, 0);
    coin::burn_for_testing(shares_coin);
    
    // 2. Admin adds rewards
    ts.next_tx(ADMIN);
    let rewards = TOKEN_100; // 100 deUSD rewards
    let rewards_coin = mint_deusd(&mut deusd_config, ADMIN, rewards, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );
    
    // 3. Wait for vesting to complete
    let current_time = clock::timestamp_ms(&clock);
    clock::set_for_testing(&mut clock, current_time + (8 * 3600 * 1000) + 1); // 8+ hours
    
    // 4. Check that total assets increased
    let total_assets = sdeusd::total_assets(&management, &clock);
    assert!(total_assets == initial_deposit + rewards, 1);
    
    // 5. Alice starts cooldown for half her position
    ts.next_tx(ALICE);
    let cooldown_assets = TOKEN_500;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        &mut user_cooldowns,
        &mut user_balances,
        &mut silo,
        cooldown_assets,
        &clock,
        ts.ctx()
    );
    
    // 6. Wait for cooldown to complete and unstake
    let cooldown_duration = sdeusd::cooldown_duration(&management);
    let new_time = clock::timestamp_ms(&clock) + cooldown_duration + 1;
    clock::set_for_testing(&mut clock, new_time);
    
    let unstaked_coin = sdeusd::unstake(
        &management,
        &global_config,
        &mut user_cooldowns,
        &mut silo,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    // Alice should receive exactly the cooldown amount she requested
    // Rewards are not included in cooldown amounts - they stay in the system
    assert!(coin::value(&unstaked_coin) == cooldown_assets, 2);
    
    coin::burn_for_testing(unstaked_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(user_cooldowns);
    test_scenario::return_shared(silo);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Additional Comprehensive Tests ===

// === Mint Function Tests ===

#[test]
fun test_mint_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Mint 1000 shares directly
    let shares = TOKEN_1000;
    let shares_coin = sdeusd::mint(
        &mut management,
        &global_config,
        &mut user_balances,
        shares,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    // Should receive exactly the requested shares (1:1 ratio initially)
    assert!(coin::value(&shares_coin) == shares, 0);
    assert!(sdeusd::get_user_balance_info(&user_balances, ALICE) == shares, 1);
    assert!(sdeusd::total_supply(&management) == shares, 2);
    
    coin::burn_for_testing(shares_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_mint_zero_shares_fails() {
    let (mut ts, global_config, admin_cap, deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Try to mint zero shares
    let shares_coin = sdeusd::mint(
        &mut management,
        &global_config,
        &mut user_balances,
        0,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    coin::burn_for_testing(shares_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Withdraw and Redeem Tests ===

#[test]
fun test_withdraw_success_when_no_cooldown() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0, ts.ctx());
    
    ts.next_tx(ALICE);
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Withdraw 500 assets
    let withdraw_assets = TOKEN_500;
    let (withdrawn_coin, burned_shares) = sdeusd::withdraw(
        &mut management,
        &global_config,
        &mut user_balances,
        withdraw_assets,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    // Check results
    assert!(coin::value(&withdrawn_coin) == withdraw_assets, 0);
    assert!(coin::value(&burned_shares) == 0, 1); // Placeholder coin
    assert!(sdeusd::get_user_balance_info(&user_balances, ALICE) == TOKEN_500, 2);
    
    coin::burn_for_testing(withdrawn_coin);
    coin::burn_for_testing(burned_shares);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_withdraw_fails_when_cooldown_active() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Try to withdraw when cooldown is active (default: 90 days)
    let (withdrawn_coin, burned_shares) = sdeusd::withdraw(
        &mut management,
        &global_config,
        &mut user_balances,
        TOKEN_500,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    coin::burn_for_testing(withdrawn_coin);
    coin::burn_for_testing(burned_shares);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Cooldown Shares Tests ===

#[test]
fun test_cooldown_shares_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let mut user_cooldowns = ts.take_shared<UserCooldowns>();
    let mut silo = ts.take_shared<DeUSDSilo>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Start cooldown for 500 shares
    let shares_to_cooldown = TOKEN_500;
    let assets_returned = sdeusd::cooldown_shares(
        &mut management,
        &global_config,
        &mut user_cooldowns,
        &mut user_balances,
        &mut silo,
        shares_to_cooldown,
        &clock,
        ts.ctx()
    );
    
    // Check that assets returned equals shares (1:1 ratio)
    assert!(assets_returned == shares_to_cooldown, 0);
    assert!(sdeusd::get_user_balance_info(&user_balances, ALICE) == TOKEN_500, 1);
    
    let cooldown_info = sdeusd::get_user_cooldown_info(&user_cooldowns, ALICE);
    assert!(sdeusd::cooldown_underlying_amount(&cooldown_info) == shares_to_cooldown, 2);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(user_cooldowns);
    test_scenario::return_shared(silo);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Multi-User Interaction Tests ===

#[test]
fun test_multiple_users_deposit_and_rewards() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    
    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());
    
    let clock = clock::create_for_testing(ts.ctx());
    
    // ALICE deposits 1000 tokens
    ts.next_tx(ALICE);
    let alice_deposit = TOKEN_1000;
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, alice_deposit, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // BOB deposits 500 tokens
    ts.next_tx(BOB);
    let bob_deposit = TOKEN_500;
    let deusd_coin = mint_deusd(&mut deusd_config, BOB, bob_deposit, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        BOB,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Admin adds rewards
    ts.next_tx(ADMIN);
    let rewards = TOKEN_100;
    let rewards_coin = mint_deusd(&mut deusd_config, ADMIN, rewards, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );
    
    // Check balances before vesting
    assert!(sdeusd::get_user_balance_info(&user_balances, ALICE) == alice_deposit, 0);
    assert!(sdeusd::get_user_balance_info(&user_balances, BOB) == bob_deposit, 1);
    assert!(sdeusd::total_supply(&management) == alice_deposit + bob_deposit, 2);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Mathematical Edge Cases ===

#[test]
fun test_deposit_with_existing_rewards_share_calculation() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    
    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());
    
    let mut clock = clock::create_for_testing(ts.ctx());
    
    // ALICE deposits first
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Admin adds rewards and waits for vesting
    ts.next_tx(ADMIN);
    let rewards = TOKEN_100;
    let rewards_coin = mint_deusd(&mut deusd_config, ADMIN, rewards, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );
    
    // Wait for vesting to complete
    let current_time = clock::timestamp_ms(&clock);
    clock::set_for_testing(&mut clock, current_time + (8 * 3600 * 1000) + 1);
    
    // Now total assets = 1000 + 100 = 1100, total supply = 1000
    // BOB deposits 550 assets, should get (550 * 1000) / 1100 = 500 shares
    ts.next_tx(BOB);
    let bob_deposit = TOKEN_500 + TOKEN_50; // 550
    let deusd_coin = mint_deusd(&mut deusd_config, BOB, bob_deposit, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        BOB,
        &clock,
        ts.ctx()
    );
    
    let bob_shares = coin::value(&shares_coin);
    let expected_shares = (bob_deposit * TOKEN_1000) / (TOKEN_1000 + TOKEN_100);
    assert!(bob_shares == expected_shares, 0);
    
    coin::burn_for_testing(shares_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Min Shares Violation Tests ===

#[test]
fun test_deposit_meets_min_shares_requirement() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Deposit exactly the minimum amount
    let min_deposit = MIN_SHARES; // 1 token
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, min_deposit, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    assert!(coin::value(&shares_coin) == min_deposit, 0);
    assert!(sdeusd::total_supply(&management) == min_deposit, 1);
    
    coin::burn_for_testing(shares_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === View Function Edge Cases ===

#[test]
fun test_max_withdraw_and_redeem_functions() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Initial deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Test max functions
    let max_withdraw = sdeusd::max_withdraw_user(&management, &user_balances, ALICE, &clock);
    let max_redeem = sdeusd::max_redeem_user(&management, &user_balances, ALICE);
    
    assert!(max_withdraw == TOKEN_1000, 0); // 1:1 ratio initially
    assert!(max_redeem == TOKEN_1000, 1);
    
    // Test for user with no balance
    let max_withdraw_bob = sdeusd::max_withdraw_user(&management, &user_balances, BOB, &clock);
    let max_redeem_bob = sdeusd::max_redeem_user(&management, &user_balances, BOB);
    
    assert!(max_withdraw_bob == 0, 2);
    assert!(max_redeem_bob == 0, 3);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Redeem Function Tests ===

#[test]
fun test_redeem_success_when_no_cooldown() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Set cooldown duration to zero to enable redeem
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0, ts.ctx());
    
    ts.next_tx(ALICE);
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Redeem 500 shares
    let redeem_shares = TOKEN_500;
    let (redeemed_assets, burned_shares) = sdeusd::redeem(
        &mut management,
        &global_config,
        &mut user_balances,
        redeem_shares,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    // Check results
    assert!(coin::value(&redeemed_assets) == redeem_shares, 0); // 1:1 ratio
    assert!(coin::value(&burned_shares) == 0, 1); // Placeholder coin
    assert!(sdeusd::get_user_balance_info(&user_balances, ALICE) == TOKEN_500, 2);
    
    coin::burn_for_testing(redeemed_assets);
    coin::burn_for_testing(burned_shares);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_redeem_fails_when_cooldown_active() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Try to redeem when cooldown is active (default: 90 days)
    let (redeemed_assets, burned_shares) = sdeusd::redeem(
        &mut management,
        &global_config,
        &mut user_balances,
        TOKEN_500,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    coin::burn_for_testing(redeemed_assets);
    coin::burn_for_testing(burned_shares);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Preview Function Tests ===

#[test]
fun test_preview_withdraw_and_redeem_accuracy() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    
    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());
    
    let mut clock = clock::create_for_testing(ts.ctx());
    
    // ALICE deposits first
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Test preview functions with 1:1 ratio
    let preview_withdraw_assets = sdeusd::preview_withdraw(&management, TOKEN_500, &clock);
    let preview_redeem_assets = sdeusd::preview_redeem(&management, TOKEN_500, &clock);
    
    assert!(preview_withdraw_assets == TOKEN_500, 0); // Should be 1:1 initially
    assert!(preview_redeem_assets == TOKEN_500, 1); // Should be 1:1 initially
    
    // Add rewards to change the share price
    ts.next_tx(ADMIN);
    let rewards = TOKEN_100;
    let rewards_coin = mint_deusd(&mut deusd_config, ADMIN, rewards, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );
    
    // Wait for vesting to complete
    let current_time = clock::timestamp_ms(&clock);
    clock::set_for_testing(&mut clock, current_time + (8 * 3600 * 1000) + 1);
    
    // Now test with changed ratio (total assets = 1100, total supply = 1000)
    let preview_withdraw_after = sdeusd::preview_withdraw(&management, TOKEN_550, &clock); // 550 assets
    let preview_redeem_after = sdeusd::preview_redeem(&management, TOKEN_500, &clock); // 500 shares
    
    // For withdraw: Need (550 * 1000) / 1100 = 500 shares to get 550 assets
    assert!(preview_withdraw_after == TOKEN_500, 2);
    
    // For redeem: Get (500 * 1100) / 1000 = 550 assets for 500 shares
    assert!(preview_redeem_after == TOKEN_550, 3);
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Zero Amount Edge Cases ===

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_withdraw_zero_amount_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0, ts.ctx());
    
    ts.next_tx(ALICE);
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Try to withdraw zero amount
    let (withdrawn_coin, burned_shares) = sdeusd::withdraw(
        &mut management,
        &global_config,
        &mut user_balances,
        0, // Zero amount
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    coin::burn_for_testing(withdrawn_coin);
    coin::burn_for_testing(burned_shares);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_redeem_zero_shares_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Set cooldown duration to zero to enable redeem
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0, ts.ctx());
    
    ts.next_tx(ALICE);
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Try to redeem zero shares
    let (redeemed_assets, burned_shares) = sdeusd::redeem(
        &mut management,
        &global_config,
        &mut user_balances,
        0, // Zero shares
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    coin::burn_for_testing(redeemed_assets);
    coin::burn_for_testing(burned_shares);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Insufficient Balance Tests ===

#[test]
#[expected_failure(abort_code = sdeusd::EExcessiveWithdrawAmount)]
fun test_withdraw_exceeds_balance_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    
    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0, ts.ctx());
    
    ts.next_tx(ALICE);
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // First deposit (only 1000)
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // Try to withdraw more than balance
    let (withdrawn_coin, burned_shares) = sdeusd::withdraw(
        &mut management,
        &global_config,
        &mut user_balances,
        TOKEN_1000 + TOKEN_100, // More than deposited
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    coin::burn_for_testing(withdrawn_coin);
    coin::burn_for_testing(burned_shares);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Complex Mathematical Cases ===

#[test]
fun test_precision_with_small_amounts() {
    let (mut ts, global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ALICE);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    let clock = clock::create_for_testing(ts.ctx());
    
    // Test with minimum shares amount
    let small_amount = MIN_SHARES; // Use minimum required shares
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, small_amount, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    
    // Should get exactly the same amount of shares
    assert!(coin::value(&shares_coin) == small_amount, 0);
    assert!(sdeusd::get_user_balance_info(&user_balances, ALICE) == small_amount, 1);
    
    coin::burn_for_testing(shares_coin);
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}

// === Vesting Edge Cases ===

#[test]
fun test_multiple_reward_distributions() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config) = setup_complete();
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<StdeUSDManagement>();
    let mut user_balances = ts.take_shared<UserBalances>();
    
    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());
    
    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);
    
    // ALICE deposits first
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, ALICE, TOKEN_1000, &mut ts);
    let shares_coin = sdeusd::deposit(
        &mut management,
        &global_config,
        &mut user_balances,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );
    coin::burn_for_testing(shares_coin);
    
    // First reward distribution
    ts.next_tx(ADMIN);
    let rewards1 = TOKEN_100;
    let rewards_coin1 = mint_deusd(&mut deusd_config, ADMIN, rewards1, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin1,
        &clock,
        ts.ctx()
    );
    
    // Wait 4 hours (half vesting)
    clock::set_for_testing(&mut clock, start_time + (4 * 3600 * 1000));
    
    // Check that first distribution is half vested
    let unvested_before_second = sdeusd::get_unvested_amount(&management, &clock);
    assert!(unvested_before_second == TOKEN_50, 0); // 50 remaining from first
    
    // Wait for first distribution to complete before second
    clock::set_for_testing(&mut clock, start_time + (8 * 3600 * 1000) + 1);
    assert!(sdeusd::get_unvested_amount(&management, &clock) == 0, 1); // Should be fully vested
    
    // Now add second reward distribution
    let rewards2 = TOKEN_50;
    let rewards_coin2 = mint_deusd(&mut deusd_config, ADMIN, rewards2, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin2,
        &clock,
        ts.ctx()
    );
    
    // Check that second distribution is fully unvested
    let unvested_amount = sdeusd::get_unvested_amount(&management, &clock);
    assert!(unvested_amount == TOKEN_50, 2); // Only the second distribution
    
    test_scenario::return_shared(management);
    test_scenario::return_shared(user_balances);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    admin_cap::destroy_for_test(admin_cap);
    clock::destroy_for_testing(clock);
    ts.end();
}
