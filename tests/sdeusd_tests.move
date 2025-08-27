#[test_only]
module elixir::sdeusd_tests;

use elixir::clock_utils;
use elixir::test_utils;
use elixir::sdeusd::{Self, SdeUSDManagement, SDEUSD};
use elixir::deusd::{Self, DEUSD, DeUSDConfig};
use elixir::config::{Self, GlobalConfig};
use elixir::admin_cap::{Self, AdminCap};
use elixir::roles;
use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::coin::Coin;
use sui::deny_list;
use sui::test_utils::assert_eq;

const ADMIN: address = @0xad;
const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;

const ONE_HOUR_SECONDS: u64 = 3600;
const ONE_HOUR_MILLIS: u64 = 3600 * 1000;
const VESTING_PERIOD_MILLIS: u64 = 8 * 3600 * 1000;

// === Initialization Tests ===

#[test]
fun test_initialization() {
    let (mut ts, global_config, admin_cap, deusd_config, management) = setup_test();
    let clock = clock::create_for_testing(ts.ctx());

    // Test that initial state is correct
    assert!(sdeusd::get_unvested_amount(&management, &clock) == 0);
    assert!(sdeusd::total_supply(&management) == 0);
    assert!(sdeusd::cooldown_duration(&management) == 90 * 86400); // 90 days
    assert!(sdeusd::total_assets(&management, &clock) == 0);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Role Management Tests ===

#[test]
fun test_role_management() {
    let (ts, mut global_config, admin_cap, deusd_config, management) = setup_test();

    // Grant rewarder role to ALICE
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_rewarder());

    // Grant blacklist manager role to BOB
    config::add_role(&admin_cap, &mut global_config, BOB, roles::role_blacklist_manager());

    // Verify roles were granted
    assert!(global_config.has_role(ALICE, roles::role_rewarder()));
    assert!(global_config.has_role(BOB, roles::role_blacklist_manager()));

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Blacklist Management Tests ===

#[test]
fun test_blacklist_management() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role to admin
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    // Add ALICE to soft blacklist
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, ALICE, false, ts.ctx());

    // Add BOB to full blacklist
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, BOB, true, ts.ctx());

    // Verify blacklist status
    assert!(sdeusd::is_soft_restricted(&management, ALICE));
    assert!(sdeusd::is_full_restricted(&management, BOB));

    // Remove from blacklists
    sdeusd::remove_from_blacklist(&mut management, &global_config, &mut deny_list, ALICE, false, ts.ctx());
    sdeusd::remove_from_blacklist(&mut management, &global_config, &mut deny_list, BOB, true, ts.ctx());

    // Verify removal
    assert!(!sdeusd::is_soft_restricted(&management, ALICE));
    assert!(!sdeusd::is_full_restricted(&management, BOB));

    sui::test_utils::destroy(deny_list);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::ENotAuthorized)]
fun test_blacklist_unauthorized_fails() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Try to blacklist without proper role
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, BOB, false, ts.ctx());

    sui::test_utils::destroy(deny_list);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::ENotAuthorized)]
fun test_remove_from_blacklist_unauthorized_fails() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role to admin and blacklist ALICE
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, ALICE, false, ts.ctx());

    // Try to remove from blacklist without proper role (using BOB who doesn't have the role)
    ts.next_tx(BOB);
    sdeusd::remove_from_blacklist(&mut management, &global_config, &mut deny_list, ALICE, false, ts.ctx());

    sui::test_utils::destroy(deny_list);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_remove_from_blacklist_non_existent_user() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role to admin
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    // Verify ALICE is not blacklisted initially
    assert!(!sdeusd::is_soft_restricted(&management, ALICE));
    assert!(!sdeusd::is_full_restricted(&management, ALICE));

    // Try to remove ALICE from soft blacklist (should not fail, just do nothing)
    sdeusd::remove_from_blacklist(&mut management, &global_config, &mut deny_list, ALICE, false, ts.ctx());

    // Try to remove ALICE from full blacklist (should not fail, just do nothing)
    sdeusd::remove_from_blacklist(&mut management, &global_config, &mut deny_list, ALICE, true, ts.ctx());

    // Verify ALICE is still not blacklisted
    assert!(!sdeusd::is_soft_restricted(&management, ALICE));
    assert!(!sdeusd::is_full_restricted(&management, ALICE));

    sui::test_utils::destroy(deny_list);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_remove_from_blacklist_wrong_type() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role to admin
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    // Add ALICE to soft blacklist only
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, ALICE, false, ts.ctx());
    assert!(sdeusd::is_soft_restricted(&management, ALICE));
    assert!(!sdeusd::is_full_restricted(&management, ALICE));

    // Try to remove ALICE from full blacklist (she's only in soft blacklist)
    sdeusd::remove_from_blacklist(&mut management, &global_config, &mut deny_list, ALICE, true, ts.ctx());

    // ALICE should still be in soft blacklist since we removed from wrong type
    assert!(sdeusd::is_soft_restricted(&management, ALICE));
    assert!(!sdeusd::is_full_restricted(&management, ALICE));

    // Now remove from correct type (soft blacklist)
    sdeusd::remove_from_blacklist(&mut management, &global_config, &mut deny_list, ALICE, false, ts.ctx());

    // Now ALICE should be completely unblacklisted
    assert!(!sdeusd::is_soft_restricted(&management, ALICE));
    assert!(!sdeusd::is_full_restricted(&management, ALICE));

    sui::test_utils::destroy(deny_list);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Cooldown Duration Tests ===

#[test]
fun test_cooldown_duration_setting() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to 7 days
    let new_duration = 7 * 24 * 60 * 60; // 7 days in seconds
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, new_duration);

    // Verify the duration was set
    assert!(sdeusd::cooldown_duration(&management) == new_duration);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EInvalidCooldown)]
fun test_cooldown_duration_too_long_fails() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Try to set cooldown duration longer than maximum (90 days)
    let invalid_duration = 91 * 24 * ONE_HOUR_MILLIS; // 91 days
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, invalid_duration);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Rewards Tests ===

#[test]
fun test_transfer_in_rewards_success() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Grant rewarder role to ALICE
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_rewarder());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let rewards_coin = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);

    // Transfer rewards
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );

    // Check that rewards were added to balance but are still vesting
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 100_000_000);
    assert_eq(sdeusd::total_assets(&management, &clock), 0); // Should be 0 since all rewards are vesting

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::ENotAuthorized)]
fun test_transfer_in_rewards_unauthorized_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let rewards_coin = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);

    // Try to transfer rewards without rewarder role
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_transfer_in_rewards_zero_amount_fails() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

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

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test, expected_failure(abort_code = elixir::sdeusd::EStillVesting)]
fun test_transfer_in_rewards_while_vesting_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // First rewards transfer
    let rewards_coin1 = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin1,
        &clock,
        ts.ctx()
    );

    // Advance time by 4 hours (still within vesting period)
    let mid_vesting_time = start_time + (4 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, mid_vesting_time);

    // Try to transfer more rewards while still vesting - should fail
    let rewards_coin2 = mint_deusd(&mut deusd_config, 50_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin2,
        &clock,
        ts.ctx()
    );

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_transfer_in_rewards_after_vesting_period_succeeds() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    ts.next_tx(ALICE);
    let initial_assets = 100_000_000;
    let mut deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    let shares = 100_000_000;
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        shares,
        ALICE,
        &clock,
        ts.ctx()
    );
    deusd_coin.burn_for_testing();

    ts.next_tx(ADMIN);
    // First rewards transfer
    let rewards_coin1 = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin1,
        &clock,
        ts.ctx()
    );

    // Verify first transfer vesting state
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 100_000_000);

    // Advance time past vesting period (8+ hours)
    let post_vesting_time = start_time + (9 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, post_vesting_time);

    // Verify vesting is complete
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets + 100_000_000);

    // Second rewards transfer should succeed
    let rewards_coin2 = mint_deusd(&mut deusd_config, 50_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin2,
        &clock,
        ts.ctx()
    );

    // Verify second transfer updated vesting state
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 50_000_000);
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets + 100_000_000); // Previous rewards fully vested

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_transfer_in_rewards_exactly_at_vesting_end() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // First rewards transfer
    let rewards_coin1 = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin1,
        &clock,
        ts.ctx()
    );

    // Advance time to exactly vesting period end (8 hours)
    let vesting_end_time = start_time + (8 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, vesting_end_time);

    // Verify vesting is exactly complete
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);

    // Second rewards transfer should succeed at exact vesting end
    let rewards_coin2 = mint_deusd(&mut deusd_config, 75_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin2,
        &clock,
        ts.ctx()
    );

    // Verify second transfer state
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 75_000_000);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_transfer_in_rewards_multiple_cycles() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // Initial deposit to ensure supply is present
    ts.next_tx(ALICE);
    let initial_deusd = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, initial_deusd, ALICE, &clock, ts.ctx());

    ts.next_tx(ADMIN);
    // First cycle: 100 tokens
    let rewards_coin1 = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin1,
        &clock,
        ts.ctx()
    );

    // Verify initial vesting state
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 100_000_000);

    // Wait for full vesting + extra time
    let time1 = start_time + (10 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, time1);

    // Second cycle: 200 tokens
    let rewards_coin2 = mint_deusd(&mut deusd_config, 200_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin2,
        &clock,
        ts.ctx()
    );

    // Verify second cycle state
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 200_000_000);
    assert_eq(sdeusd::total_assets(&management, &clock), 1100_000_000); // Initial deposit + first batch fully vested

    // Wait for second vesting
    let time2 = time1 + (8 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, time2);

    // Third cycle: 50 tokens
    let rewards_coin3 = mint_deusd(&mut deusd_config, 50_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin3,
        &clock,
        ts.ctx()
    );

    // Verify third cycle state
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 50_000_000);
    assert_eq(sdeusd::total_assets(&management, &clock), 1300_000_000); // Initial deposit + first two batches fully vested

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_transfer_in_rewards_vesting_state_updates() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    ts.next_tx(ALICE);
    let initial_assets = 100_000_000;
    let mut deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    let shares = 100_000_000;
    sdeusd::mint(&mut management, &global_config, &mut deusd_coin, shares, ALICE, &clock, ts.ctx());
    deusd_coin.burn_for_testing();

    // Initial state - no vesting
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);

    ts.next_tx(ADMIN);
    // Transfer rewards
    let rewards_coin = mint_deusd(&mut deusd_config, 120_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );

    // Verify vesting state immediately after transfer
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 120_000_000);
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets + 0);

    // Test at 25% vesting (2 hours)
    let time_25_percent = start_time + (2 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, time_25_percent);
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 90_000_000); // 75% left
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets + 30_000_000); // 25% vested

    // Test at 75% vesting (6 hours)
    let time_75_percent = start_time + (6 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, time_75_percent);
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 30_000_000); // 25% left
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets + 90_000_000); // 75% vested

    // Test at 100% vesting (8 hours)
    let time_100_percent = start_time + (8 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, time_100_percent);
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets + 120_000_000); // Fully vested

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_multiple_reward_distributions() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // ALICE deposits first
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    shares_coin.burn_for_testing();

    // First reward distribution
    ts.next_tx(ADMIN);
    let rewards1 = 100_000_000;
    let rewards_coin1 = mint_deusd(&mut deusd_config, rewards1, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin1,
        &clock,
        ts.ctx()
    );

    // Wait 4 hours (half vesting)
    clock::set_for_testing(&mut clock, start_time + VESTING_PERIOD_MILLIS / 2);

    // Check that first distribution is half vested
    let unvested_before_second = sdeusd::get_unvested_amount(&management, &clock);
    assert_eq(unvested_before_second, 50_000_000); // 50 remaining from first

    // Wait for first distribution to complete before second
    clock::set_for_testing(&mut clock, start_time + VESTING_PERIOD_MILLIS);
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0); // Should be fully vested

    // Now add second reward distribution
    let rewards2 = 50_000_000;
    let rewards_coin2 = mint_deusd(&mut deusd_config, rewards2, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin2,
        &clock,
        ts.ctx()
    );

    // Check that second distribution is fully unvested
    let unvested_amount = sdeusd::get_unvested_amount(&management, &clock);
    assert_eq(unvested_amount, 50_000_000); // Only the second distribution

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}


// === Preview Function Tests ===

#[test]
fun test_preview_functions() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());

    assert_eq(sdeusd::preview_mint(&management, 1000_000_000, &clock), 1000_000_000);
    assert_eq(sdeusd::preview_deposit(&management, 1000_000_000, &clock), 1000_000_000);

    // ALICE deposits first
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    shares_coin.burn_for_testing();

    // Test preview functions with 1:1 ratio
    assert_eq(sdeusd::preview_mint(&management, 1000_000_000, &clock), 1000_000_000);
    assert_eq(sdeusd::preview_deposit(&management, 1000_000_000, &clock), 1000_000_000);
    assert_eq(sdeusd::preview_withdraw(&management, 500_000_000, &clock), 500_000_000);
    assert_eq(sdeusd::preview_redeem(&management, 500_000_000, &clock), 500_000_000);

    // Add rewards to change the share price
    ts.next_tx(ADMIN);
    let rewards = 200_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );

    // Advance a half vesting period
    test_utils::advance_time(&mut clock, VESTING_PERIOD_MILLIS / 2);

    assert_eq(sdeusd::total_assets(&management, &clock), 1100_000_000);

    // Now, the ratio should be 1100 assets to 1000 shares
    assert_eq(sdeusd::preview_mint(&management, 1000_000_000, &clock), 1100_000_000);
    assert_eq(sdeusd::preview_deposit(&management, 1100_000_000, &clock), 1000_000_000);
    assert_eq(sdeusd::preview_withdraw(&management, 550_000_000, &clock), 500_000_000);
    assert_eq(sdeusd::preview_redeem(&management, 500_000_000, &clock), 550_000_000);

    // Advance a half vesting period to complete the vesting
    test_utils::advance_time(&mut clock, VESTING_PERIOD_MILLIS / 2);

    // Now, the ratio should be 1200 assets to 1000 shares
    assert_eq(sdeusd::preview_mint(&management, 1000_000_000, &clock), 1200_000_000);
    assert_eq(sdeusd::preview_deposit(&management, 1200_000_000, &clock), 1000_000_000);
    assert_eq(sdeusd::preview_withdraw(&management, 600_000_000, &clock), 500_000_000);
    assert_eq(sdeusd::preview_redeem(&management, 500_000_000, &clock), 600_000_000);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Mint Function Tests ===

#[test]
fun test_mint_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Mint some deUSD for ALICE to cover the mint cost
    let mut deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Mint 1000 shares directly
    let shares = 1000_000_000;
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        shares,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Should receive exactly the requested shares (1:1 ratio initially)
    assert_eq(shares_coin.value(), shares);
    assert_eq(sdeusd::total_supply(&management), shares);

    shares_coin.burn_for_testing();
    deusd_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_mint_zero_shares_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let mut deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to mint zero shares
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        0,
        ALICE,
        &clock,
        ts.ctx()
    );

    deusd_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_mint_min_shares_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let mut deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to mint zero shares
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        1_000_000, // Minimum shares
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    assert_eq(shares_coin.value(), 1_000_000);
    shares_coin.burn_for_testing();

    deusd_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EMinSharesViolation)]
fun test_mint_min_shares_violation_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let mut deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to mint zero shares
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        999_999,
        ALICE,
        &clock,
        ts.ctx()
    );

    deusd_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_mint_zero_assets_coin_fails() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Create an empty coin (0 value)
    let mut deusd_coin = coin::zero<DEUSD>(ts.ctx());

    // Try to mint with empty coin - should fail on first assertion
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        1000_000_000,
        ALICE,
        &clock,
        ts.ctx()
    );

    deusd_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_mint_soft_restricted_sender_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role and blacklist ALICE
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(
        &mut management,
        &global_config,
        &mut deny_list,
        ALICE,
        false,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let mut deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to mint as soft restricted user
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        1000_000_000,
        ALICE,
        &clock,
        ts.ctx()
    );

    deusd_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_mint_soft_restricted_receiver_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role and blacklist BOB (receiver)
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, BOB, false, ts.ctx()); // soft restriction

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let mut deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to mint to soft restricted receiver
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        1000_000_000,
        BOB, // soft restricted receiver
        &clock,
        ts.ctx()
    );

    deusd_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_mint_full_restricted_sender_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role and blacklist ALICE
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, ALICE, true, ts.ctx());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let mut deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to mint as full restricted user
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        1000_000_000,
        ALICE,
        &clock,
        ts.ctx()
    );

    deusd_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_mint_full_restricted_receiver_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role and blacklist BOB (receiver)
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, BOB, true, ts.ctx()); // full restriction

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let mut deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to mint to soft restricted receiver
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        1000_000_000,
        BOB, // full restricted receiver
        &clock,
        ts.ctx()
    );

    deusd_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_mint_with_different_receiver() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let mut deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    let initial_balance = deusd_coin.value();

    // Alice mints shares for BOB
    let shares = 500_000_000;
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        shares,
        BOB, // receiver is different from sender
        &clock,
        ts.ctx()
    );

    // Check that BOB received the shares
    ts.next_tx(BOB);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(BOB);
    assert_eq(shares_coin.value(), shares);
    test_scenario::return_to_address(BOB, shares_coin);

    // Check that Alice still has remaining deUSD
    ts.next_tx(ALICE);
    let remaining_balance = deusd_coin.value();
    assert_eq(remaining_balance, initial_balance - shares);

    deusd_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure]
fun test_mint_insufficient_assets_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Create coin with small amount
    let mut deusd_coin = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);

    // Try to mint more shares than assets available
    // This should fail when trying to split more than available
    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        1000_000_000,
        ALICE,
        &clock,
        ts.ctx()
    );

    deusd_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_mint_with_existing_supply_and_rewards() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());

    // First, make an initial deposit to establish supply
    ts.next_tx(ALICE);
    let initial_deposit = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        initial_deposit,
        ALICE,
        &clock,
        ts.ctx()
    );

    // Add rewards to change the ratio
    ts.next_tx(ADMIN);
    let rewards = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards,
        &clock,
        ts.ctx()
    );

    test_utils::advance_time(&mut clock, VESTING_PERIOD_MILLIS);

    // Now, the ratio assets:shares is 1100:1000 (after rewards)
    // With total_assets = 1100, total_supply = 1000, minting 500 shares
    // preview_mint(500) = ceil((500 * 1100) / 1000) = ceil(550) = 550

    ts.next_tx(BOB);
    let mut deusd_coin = mint_deusd(&mut deusd_config, 550_000_000, &mut ts);
    let shares_to_mint = 500_000_000;

    assert_eq(sdeusd::preview_mint(&management, shares_to_mint, &clock), 550_000_000);

    sdeusd::mint(
        &mut management,
        &global_config,
        &mut deusd_coin,
        shares_to_mint,
        BOB,
        &clock,
        ts.ctx()
    );

    // Check that BOB received the shares
    ts.next_tx(BOB);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(BOB);
    assert_eq(shares_coin.value(), shares_to_mint);
    test_scenario::return_to_address(BOB, shares_coin);

    assert_eq(deusd_coin.value(), 0);

    deusd_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Deposit Tests ===

#[test]
fun test_deposit_success() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ADMIN);
    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    ts.next_tx(ALICE);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Check that shares were received (1:1 ratio initially)
    assert!(shares_coin.value() == 1000_000_000);
    assert!(sdeusd::total_supply(&management) == 1000_000_000);
    shares_coin.burn_for_testing();

    // Add rewards to change the ratio
    ts.next_tx(ADMIN);
    let rewards = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards,
        &clock,
        ts.ctx()
    );

    test_utils::advance_time(&mut clock, VESTING_PERIOD_MILLIS);

    // Now, the ratio assets:shares is 1100:1000 (after rewards)
    // With total_assets = 1100, total_supply = 1000, minting 500 shares
    // preview_mint(500) = ceil((500 * 1100) / 1000) = ceil(550) = 550

    ts.next_tx(BOB);
    let deusd_coin = mint_deusd(&mut deusd_config, 550_000_000, &mut ts);
    assert_eq(sdeusd::preview_deposit(&management, 550_000_000, &clock), 500_000_000);

    ts.next_tx(ALICE);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    assert_eq(shares_coin.value(), 500_000_000);
    shares_coin.burn_for_testing();

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_deposit_full_restricted_sender_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role and blacklist ALICE
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, ALICE, true, ts.ctx());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Mint deUSD for restricted user
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to deposit as full restricted user
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_deposit_full_restricted_receiver_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role and blacklist ALICE
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, BOB, true, ts.ctx());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Mint deUSD for restricted user
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        BOB, // full restricted receiver
        &clock,
        ts.ctx()
    );

    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_deposit_zero_amount_fails() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    let clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // Try to deposit zero amount
    let zero_coin = coin::zero<DEUSD>(ts.ctx());
    sdeusd::deposit(
        &mut management,
        &global_config,
        zero_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_deposit_min_shares_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    let clock = clock::create_for_testing(ts.ctx());

    let deusd_coin = mint_deusd(&mut deusd_config, 1_000_000, &mut ts);

    ts.next_tx(ALICE);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    assert_eq(shares_coin.value(), 1_000_000);
    shares_coin.burn_for_testing();

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EMinSharesViolation)]
fun test_deposit_min_shares_violation_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let deusd_coin = mint_deusd(&mut deusd_config, 999_999, &mut ts);

    ts.next_tx(ALICE);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_deposit_soft_restricted_caller_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role and blacklist ALICE
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(
        &mut management,
        &global_config,
        &mut deny_list,
        ALICE,
        false,
        ts.ctx()
    ); // soft restriction

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Mint deUSD for restricted user
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to deposit as soft restricted user
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_deposit_soft_restricted_receiver_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role and blacklist BOB (receiver)
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, BOB, false, ts.ctx()); // soft restriction

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Mint deUSD for normal user
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);

    // Try to deposit to soft restricted receiver
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        BOB, // soft restricted receiver
        &clock,
        ts.ctx()
    );

    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_deposit_with_receiver_different_from_sender() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Alice deposits but sends shares to Bob
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        BOB, // receiver is different from sender
        &clock,
        ts.ctx()
    );

    // Check that BOB received the shares
    ts.next_tx(BOB);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(BOB);
    assert_eq(shares_coin.value(), 1000_000_000); // 1:1 ratio for first deposit
    test_scenario::return_to_address(BOB, shares_coin);

    // Check total assets and supply
    assert_eq(sdeusd::total_assets(&management, &clock), 1000_000_000);
    assert_eq(sdeusd::total_supply(&management), 1000_000_000);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Withdraw and Redeem Tests ===

#[test]
fun test_withdraw_success_when_no_cooldown() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Withdraw 500 assets
    let withdraw_assets = 500_000_000;
    sdeusd::withdraw(
        &mut management,
        &global_config,
        withdraw_assets,
        &mut shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let withdrawn_coin = ts.take_from_address<Coin<DEUSD>>(ALICE);

    // Check results
    assert_eq(withdrawn_coin.value(), withdraw_assets);
    assert_eq(shares_coin.value(), 500_000_000); // Remaining shares

    withdrawn_coin.burn_for_testing();
    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_withdraw_fails_when_cooldown_active() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to withdraw when cooldown is active (default: 90 days)
    sdeusd::withdraw(
        &mut management,
        &global_config,
        500_000_000,
        &mut shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_withdraw_zero_assets_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to withdraw 0 assets - should fail
    sdeusd::withdraw(
        &mut management,
        &global_config,
        0, // Zero assets
        &mut shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_withdraw_min_shares_remaining_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Withdraw 999_000_000 shares -> 1_000_000 shares remaining == min shares
    sdeusd::withdraw(
        &mut management,
        &global_config,
        999_000_000,
        &mut shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    assert_eq(shares_coin.value(), 1_000_000); // Remaining shares should be exactly min shares
    assert_eq(sdeusd::total_supply(&management), 1_000_000);

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EMinSharesViolation)]
fun test_withdraw_min_shares_violation_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Withdraw 999_000_001 shares -> 999_999 shares remaining -> should fail
    sdeusd::withdraw(
        &mut management,
        &global_config,
        999_000_001,
        &mut shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_withdraw_sender_full_restricted_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // Grant blacklist manager role to admin
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit (before restriction - this should work)
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Add ALICE to full restriction list
    ts.next_tx(ADMIN);
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, ALICE, true, ts.ctx());

    ts.next_tx(ALICE);
    // Try to withdraw as restricted sender - should fail
    sdeusd::withdraw(
        &mut management,
        &global_config,
        500_000_000,
        &mut shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_withdraw_receiver_full_restricted_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // Grant blacklist manager role to admin
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    // Add BOB to full restriction list  
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, BOB, true, ts.ctx());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to withdraw with restricted receiver - should fail
    sdeusd::withdraw(
        &mut management,
        &global_config,
        500_000_000,
        &mut shares_coin,
        BOB, // Restricted receiver
        ALICE,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_withdraw_owner_full_restricted_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // Grant blacklist manager role to admin
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    // Add BOB to full restriction list
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, BOB, true, ts.ctx());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to withdraw with restricted owner - should fail
    sdeusd::withdraw(
        &mut management,
        &global_config,
        500_000_000,
        &mut shares_coin,
        ALICE,
        BOB, // Restricted owner
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_withdraw_with_different_receiver_and_owner() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Withdraw with different receiver and owner
    let withdraw_assets = 500_000_000;
    sdeusd::withdraw(
        &mut management,
        &global_config,
        withdraw_assets,
        &mut shares_coin,
        ALICE,
        BOB,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let withdrawn_coin = ts.take_from_address<Coin<DEUSD>>(BOB);

    // Check results
    assert_eq(withdrawn_coin.value(), withdraw_assets);
    assert_eq(shares_coin.value(), 500_000_000); // Remaining shares

    withdrawn_coin.burn_for_testing();
    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_withdraw_partial_amount() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Large deposit
    let initial_deposit = 10000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_deposit, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    // let initial_shares = shares_coin.value(); // Not needed for this test

    // Multiple partial withdrawals
    let withdraw1 = 1000_000_000;
    sdeusd::withdraw(
        &mut management,
        &global_config,
        withdraw1,
        &mut shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let withdrawn_coin1 = ts.take_from_address<Coin<DEUSD>>(ALICE);
    assert_eq(withdrawn_coin1.value(), withdraw1);

    let withdraw2 = 2000_000_000;
    sdeusd::withdraw(
        &mut management,
        &global_config,
        withdraw2,
        &mut shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let withdrawn_coin2 = ts.take_from_address<Coin<DEUSD>>(ALICE);
    assert_eq(withdrawn_coin2.value(), withdraw2);

    // Check final shares match expected amount
    let remaining_assets = initial_deposit - withdraw1 - withdraw2;
    let expected_remaining_shares = remaining_assets; // 1:1 ratio
    assert_eq(shares_coin.value(), expected_remaining_shares);

    withdrawn_coin1.burn_for_testing();
    withdrawn_coin2.burn_for_testing();
    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_withdraw_with_rewards_affects_ratio() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero to enable withdraw
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    ts.next_tx(ALICE);
    let mut clock = clock::create_for_testing(ts.ctx());

    // Initial deposit
    let initial_deposit = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_deposit, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    // Add rewards to change the ratio
    ts.next_tx(ADMIN);
    let rewards_coin = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );

    // Advance time past rewards distribution
    test_utils::advance_time(&mut clock, VESTING_PERIOD_MILLIS + 1);

    // Now ration assets/shares is 11:10

    ts.next_tx(ALICE);
    // Now total_assets = 1100, total_supply = 1000, ratio = 11:10
    let withdraw_assets = 550_000_000;
    let expected_shares_burned = 500_000_000;

    assert_eq(sdeusd::preview_withdraw(&management, withdraw_assets, &clock), expected_shares_burned);

    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    let shares_before = shares_coin.value();
    sdeusd::withdraw(
        &mut management,
        &global_config,
        withdraw_assets,
        &mut shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let withdrawn_coin = ts.take_from_address<Coin<DEUSD>>(ALICE);
    assert_eq(withdrawn_coin.value(), withdraw_assets);

    let shares_after = shares_coin.value();
    let actual_shares_burned = shares_before - shares_after;
    assert_eq(actual_shares_burned, expected_shares_burned);

    withdrawn_coin.burn_for_testing();
    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Redeem Tests ===

#[test]
fun test_redeem_success_when_no_cooldown() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero to enable redeem
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit to get shares
    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Now redeem half the shares
    let redeem_shares = 500_000_000;
    let shares_to_redeem = shares_coin.split(redeem_shares, ts.ctx());
    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_to_redeem,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let redeemed_coin = ts.take_from_address<Coin<DEUSD>>(ALICE);
    assert_eq(redeemed_coin.value(), redeem_shares); // 1:1 ratio initially
    assert_eq(shares_coin.value(), deposit_amount - redeem_shares); // Remaining shares

    redeemed_coin.burn_for_testing();
    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_redeem_fails_when_cooldown_active() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Keep default cooldown duration (90 days) - cooldown is active

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit to get shares
    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to redeem - should fail because cooldown is active
    // This should abort with EOperationNotAllowed

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = elixir::sdeusd::EOperationNotAllowed)]
fun test_redeem_fails_when_cooldown_active_actual() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // This should fail
    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_redeem_with_different_receiver_and_owner() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero to enable redeem
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Alice deposits
    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Alice redeems but sends assets to Bob
    let redeem_shares = 500_000_000;
    let shares_to_redeem = shares_coin.split(redeem_shares, ts.ctx());
    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_to_redeem,
        ALICE,
        BOB,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let redeemed_coin = ts.take_from_address<Coin<DEUSD>>(BOB);
    assert_eq(redeemed_coin.value(), redeem_shares);

    redeemed_coin.burn_for_testing();
    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_redeem_min_shares_remaining_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_coin.split(999_000_000, ts.ctx()),
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    assert_eq(sdeusd::total_supply(&management), 1_000_000); // Remaining shares should be exactly min shares

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}


#[test]
#[expected_failure(abort_code = elixir::sdeusd::EMinSharesViolation)]
fun test_redeem_min_shares_violation_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to redeem 999_000_001 -> remaining shares == 999_999 < min shares -> should fail
    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_coin.split(999_000_001, ts.ctx()),
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = elixir::sdeusd::EZeroAmount)]
fun test_redeem_zero_shares_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to redeem zero shares - should fail
    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_coin.split(0, ts.ctx()),
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = elixir::sdeusd::EOperationNotAllowed)]
fun test_redeem_sender_full_restricted_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Set cooldown duration to zero
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // Grant blacklist manager role to admin
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Alice deposits first (before being blacklisted)
    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Admin blacklists Alice (full restriction)
    ts.next_tx(ADMIN);
    sdeusd::add_to_blacklist(
        &mut management,
        &global_config,
        &mut deny_list,
        ALICE,
        true, // full blacklisting
        ts.ctx()
    );

    // Alice tries to redeem - should fail
    ts.next_tx(ALICE);
    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_coin,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = elixir::sdeusd::EOperationNotAllowed)]
fun test_redeem_receiver_full_restricted_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Admin blacklists Bob (full restriction)
    ts.next_tx(ADMIN);
    sdeusd::add_to_blacklist(
        &mut management,
        &global_config,
        &mut deny_list,
        BOB,
        true,
        ts.ctx()
    );

    // Alice tries to redeem with Bob as receiver - should fail
    ts.next_tx(ALICE);
    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_coin,
        BOB, // restricted receiver
        ALICE,
        &clock,
        ts.ctx()
    );
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = elixir::sdeusd::EOperationNotAllowed)]
fun test_redeem_owner_full_restricted_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(BOB);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Admin blacklists Alice (full restriction)
    ts.next_tx(ADMIN);
    sdeusd::add_to_blacklist(
        &mut management,
        &global_config,
        &mut deny_list,
        ALICE,
        true,
        ts.ctx()
    );

    // Bob tries to redeem Alice's shares (Alice is owner) - should fail
    ts.next_tx(BOB);
    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_coin,
        BOB,
        ALICE, // restricted owner
        &clock,
        ts.ctx()
    );
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_redeem_with_rewards_affects_ratio() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    ts.next_tx(ALICE);
    let mut clock = clock::create_for_testing(ts.ctx());

    // Initial deposit
    let initial_deposit = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_deposit, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Add rewards to change the ratio
    ts.next_tx(ADMIN);
    let rewards_coin = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );

    // Advance time past rewards distribution
    test_utils::advance_time(&mut clock, VESTING_PERIOD_MILLIS);

    // Now redeem - should get more assets than shares due to rewards
    ts.next_tx(ALICE);
    let redeem_shares = 500_000_000;
    let expected_assets = 550_000_000; // 10:11 ratio after rewards

    assert_eq(sdeusd::preview_redeem(&management, redeem_shares, &clock), expected_assets);

    let shares_to_redeem = shares_coin.split(redeem_shares, ts.ctx());
    sdeusd::redeem(
        &mut management,
        &global_config,
        shares_to_redeem,
        ALICE,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let redeemed_coin = ts.take_from_address<Coin<DEUSD>>(ALICE);
    assert_eq(redeemed_coin.value(), expected_assets);

    redeemed_coin.burn_for_testing();
    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Cooldown Tests ===

#[test]
fun test_cooldown_assets_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // First deposit to get shares
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );


    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Start cooldown for 500 assets
    let assets_to_cooldown = 500_000_000;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        assets_to_cooldown,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    // Check that shares were burned and cooldown was set
    assert_eq(shares_coin.value(), 500_000_000);

    let (cooldown_end, cooldown_amount) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_amount, assets_to_cooldown);
    assert!(cooldown_end > 0);

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_cooldown_assets_zero_cooldown_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    let clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );


    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to start cooldown when cooldown duration is zero
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        500_000_000,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}


#[test]
#[expected_failure(abort_code = sdeusd::EExcessiveWithdrawAmount)]
fun test_cooldown_assets_excessive_amount_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // First deposit to get shares
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to cooldown more assets than the max_withdraw amount allows
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        1000_000_001, // Excessive amount
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_cooldown_assets_full_restricted_user_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role and fully blacklist ALICE
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    let clock = clock::create_for_testing(ts.ctx());

    // First deposit before restriction
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    // Now blacklist ALICE (full restriction)
    ts.next_tx(ADMIN);
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, ALICE, true, ts.ctx());

    // Try to cooldown as full restricted user
    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        500_000_000,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_cooldown_assets_zero_amount_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // First deposit to get shares
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to cooldown zero assets - should fail on withdraw_to_silo assertion
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        0, // Zero assets
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_cooldown_assets_multiple_accumulate() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    let cooldown_duration = sdeusd::cooldown_duration(&management);

    ts.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = clock_utils::timestamp_seconds(&clock);

    ts.next_tx(ALICE);
    // First deposit to get shares
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // First cooldown
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        300_000_000,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    let (cooldown_end_1, cooldown_amount_1) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_end_1, start_time + cooldown_duration);
    assert_eq(cooldown_amount_1, 300_000_000);

    test_utils::advance_time(&mut clock, ONE_HOUR_MILLIS);

    // Second cooldown - should accumulate
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        200_000_000,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    let (cooldown_end_2, cooldown_amount_2) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_amount_2, 500_000_000);
    assert_eq(cooldown_end_2, start_time + ONE_HOUR_SECONDS + cooldown_duration);

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}


// === Cooldown Shares Tests ===

#[test]
fun test_cooldown_shares_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    let mut shares_coin_to_cooldown = shares_coin.split(500_000_000, ts.ctx());
    sdeusd::cooldown_shares(
        &mut management,
        &global_config,
        &mut shares_coin_to_cooldown,
        &clock,
        ts.ctx()
    );

    // Check that shares were burned and cooldown was set
    assert_eq(shares_coin_to_cooldown.value(), 0); // Remaining shares

    let (cooldown_end, cooldown_amount) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert!(cooldown_end > 0);
    assert_eq(cooldown_amount, 500_000_000);

    shares_coin.burn_for_testing();
    shares_coin_to_cooldown.destroy_zero();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_cooldown_shares_zero_cooldown_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Set cooldown duration to zero
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    let clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Try to start cooldown when cooldown duration is zero
    sdeusd::cooldown_shares(
        &mut management,
        &global_config,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_cooldown_shares_full_restricted_user_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut deny_list = deny_list::new_for_testing(ts.ctx());

    // Grant blacklist manager role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());

    let clock = clock::create_for_testing(ts.ctx());

    // First deposit before restriction
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    // Now blacklist ALICE (full restriction)
    ts.next_tx(ADMIN);
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, ALICE, true, ts.ctx());

    // Try to cooldown shares as full restricted user
    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    sdeusd::cooldown_shares(
        &mut management,
        &global_config,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EZeroAmount)]
fun test_cooldown_shares_zero_shares_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    // Create an empty shares coin
    let mut empty_shares_coin = coin::zero<SDEUSD>(ts.ctx());

    // Try to cooldown zero shares - should fail in withdraw_to_silo
    sdeusd::cooldown_shares(
        &mut management,
        &global_config,
        &mut empty_shares_coin,
        &clock,
        ts.ctx()
    );

    empty_shares_coin.destroy_zero();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_cooldown_shares_multiple_accumulate() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // First cooldown - 300 shares
    let mut shares_coin_1 = shares_coin.split(300_000_000, ts.ctx());
    sdeusd::cooldown_shares(
        &mut management,
        &global_config,
        &mut shares_coin_1,
        &clock,
        ts.ctx()
    );

    let (cooldown_end_1, cooldown_amount_1) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_amount_1, 300_000_000);

    // Second cooldown - 200 shares, should accumulate
    let mut shares_coin_2 = shares_coin.split(200_000_000, ts.ctx());
    sdeusd::cooldown_shares(
        &mut management,
        &global_config,
        &mut shares_coin_2,
        &clock,
        ts.ctx()
    );

    let (cooldown_end_2, cooldown_amount_2) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_amount_2, 500_000_000);
    assert_eq(cooldown_end_2, cooldown_end_1);

    shares_coin.burn_for_testing();
    shares_coin_1.destroy_zero();
    shares_coin_2.destroy_zero();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_cooldown_shares_with_changed_ratio() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    let cooldown_duration  = sdeusd::cooldown_duration(&management);

    ts.next_tx(ADMIN);
    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());

    // First deposit
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    // Add rewards to change the share-to-asset ratio
    ts.next_tx(ADMIN);
    let rewards = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards,
        &clock,
        ts.ctx()
    );

    test_utils::advance_time(&mut clock, VESTING_PERIOD_MILLIS);

    // Now cooldown shares when ratio is 11:10
    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    let mut shares_to_cooldown = shares_coin.split(500_000_000, ts.ctx());
    let expected_assets = 550_000_000; // 500 shares * 11/10 ratio

    let current_time = clock_utils::timestamp_seconds(&clock);

    sdeusd::cooldown_shares(
        &mut management,
        &global_config,
        &mut shares_to_cooldown,
        &clock,
        ts.ctx()
    );

    let (cooldown_end, cooldown_amount) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_end, current_time + cooldown_duration);
    assert_eq(cooldown_amount, expected_assets);

    shares_coin.burn_for_testing();
    shares_to_cooldown.destroy_zero();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Unstake Tests ===

#[test]
fun test_unstake_success() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Start cooldown
    let assets_to_cooldown = 500_000_000;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        assets_to_cooldown,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    // Advance time past cooldown period
    let cooldown_duration_in_ms = sdeusd::cooldown_duration(&management) * 1000;
    test_utils::advance_time(&mut clock, cooldown_duration_in_ms + 1);

    ts.next_tx(ALICE);
    // Unstake
    sdeusd::unstake(
        &mut management,
        &global_config,
        BOB, // Receive at different address
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let unstaked_coin = ts.take_from_address<Coin<DEUSD>>(BOB);
    assert_eq(unstaked_coin.value(), assets_to_cooldown);

    // Check that cooldown was cleared
    let (cooldown_end, cooldown_amount) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_amount, 0);
    assert_eq(cooldown_end, 0);

    shares_coin.burn_for_testing();
    unstaked_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EInvalidCooldown)]
fun test_unstake_before_cooldown_end_fails() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // First deposit and start cooldown
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        500_000_000,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    // Try to unstake immediately (before cooldown ends)
    sdeusd::unstake(
        &mut management,
        &global_config,
        ALICE,
        &clock,
        ts.ctx()
    );

    shares_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_unstake_no_cooldown_fails() {
    let (mut ts, global_config, admin_cap, _deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    let clock = clock::create_for_testing(ts.ctx());

    // Try to unstake without having any cooldown
    sdeusd::unstake(
        &mut management,
        &global_config,
        ALICE,
        &clock,
        ts.ctx()
    );

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, _deusd_config, management);
}

#[test]
fun test_unstake_with_zero_cooldown_duration() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Start cooldown with normal duration first
    let assets_to_cooldown = 500_000_000;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        assets_to_cooldown,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ADMIN);
    // Now set cooldown duration to 0 - this should allow immediate unstaking
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    ts.next_tx(ALICE);
    // Should be able to unstake immediately with zero cooldown duration
    sdeusd::unstake(
        &mut management,
        &global_config,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let unstaked_coin = ts.take_from_address<Coin<DEUSD>>(ALICE);
    assert_eq(unstaked_coin.value(), assets_to_cooldown);

    // Check that cooldown was cleared
    let (cooldown_end, cooldown_amount) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_amount, 0);
    assert_eq(cooldown_end, 0);

    shares_coin.burn_for_testing();
    unstaked_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unstake_exact_cooldown_end_time() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Start cooldown
    let assets_to_cooldown = 500_000_000;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        assets_to_cooldown,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    // Get the exact cooldown end time
    let (cooldown_end, _) = sdeusd::get_user_cooldown_info(&management, ALICE);

    // Set clock to exactly the cooldown end time
    clock::set_for_testing(&mut clock, cooldown_end * 1000);

    ts.next_tx(ALICE);
    // Should be able to unstake at exact cooldown end time
    sdeusd::unstake(
        &mut management,
        &global_config,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let unstaked_coin = ts.take_from_address<Coin<DEUSD>>(ALICE);
    assert_eq(unstaked_coin.value(), assets_to_cooldown);

    shares_coin.burn_for_testing();
    unstaked_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unstake_multiple_times_same_user() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // First deposit
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // First cooldown cycle
    let assets_to_cooldown1 = 300_000_000;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        assets_to_cooldown1,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    // Advance time past cooldown period
    let cooldown_duration_in_ms = sdeusd::cooldown_duration(&management) * 1000;
    test_utils::advance_time(&mut clock, cooldown_duration_in_ms + 1);

    ts.next_tx(ALICE);
    // First unstake
    sdeusd::unstake(
        &mut management,
        &global_config,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let unstaked_coin1 = ts.take_from_address<Coin<DEUSD>>(ALICE);
    assert_eq(unstaked_coin1.value(), assets_to_cooldown1);

    // Second cooldown cycle
    let assets_to_cooldown2 = 200_000_000;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        assets_to_cooldown2,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    // Advance time again
    test_utils::advance_time(&mut clock, cooldown_duration_in_ms + 1);

    ts.next_tx(ALICE);
    // Second unstake
    sdeusd::unstake(
        &mut management,
        &global_config,
        BOB, // Different receiver
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let unstaked_coin2 = ts.take_from_address<Coin<DEUSD>>(BOB);
    assert_eq(unstaked_coin2.value(), assets_to_cooldown2);

    // Check that cooldown was cleared
    let (cooldown_end, cooldown_amount) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_amount, 0);
    assert_eq(cooldown_end, 0);

    shares_coin.burn_for_testing();
    unstaked_coin1.burn_for_testing();
    unstaked_coin2.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unstake_with_different_receiver() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    // Regular deposit
    let deposit_amount = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, deposit_amount, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Start cooldown
    let assets_to_cooldown = 500_000_000;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        assets_to_cooldown,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    // Advance time past cooldown period
    let cooldown_duration_in_ms = sdeusd::cooldown_duration(&management) * 1000;
    test_utils::advance_time(&mut clock, cooldown_duration_in_ms + 1);

    ts.next_tx(ALICE);
    // Unstake to a different receiver (BOB)
    sdeusd::unstake(
        &mut management,
        &global_config,
        BOB, // Different receiver
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let unstaked_coin = ts.take_from_address<Coin<DEUSD>>(BOB);
    assert_eq(unstaked_coin.value(), assets_to_cooldown);

    // Check that cooldown was cleared for ALICE
    let (cooldown_end, cooldown_amount) = sdeusd::get_user_cooldown_info(&management, ALICE);
    assert_eq(cooldown_amount, 0);
    assert_eq(cooldown_end, 0);

    shares_coin.burn_for_testing();
    unstaked_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = sdeusd::EOperationNotAllowed)]
fun test_unstake_full_restricted_user_fails() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);

    // Start cooldown
    let assets_to_cooldown = 500_000_000;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        assets_to_cooldown,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    // Advance time past cooldown period
    let cooldown_duration_in_ms = sdeusd::cooldown_duration(&management) * 1000;
    test_utils::advance_time(&mut clock, cooldown_duration_in_ms + 1);

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_blacklist_manager());
    let mut deny_list = deny_list::new_for_testing(ts.ctx());
    sdeusd::add_to_blacklist(&mut management, &global_config, &mut deny_list, ALICE, true, ts.ctx());

    ts.next_tx(ALICE);
    sdeusd::unstake(&mut management, &global_config, ALICE, &clock, ts.ctx());

    shares_coin.burn_for_testing();
    sui::test_utils::destroy(deny_list);
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_staking_e2e() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Grant rewarder role
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    ts.next_tx(ALICE);
    let mut clock = clock::create_for_testing(ts.ctx());

    // Alice deposits
    let initial_deposit = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_deposit, &mut ts);
    sdeusd::deposit(
        &mut management,
        &global_config,
        deusd_coin,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let mut shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    assert_eq(shares_coin.value(), initial_deposit);

    // Admin adds rewards
    ts.next_tx(ADMIN);
    let rewards = 100_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );

    // Wait for vesting to complete
    let current_time = clock::timestamp_ms(&clock);
    clock::set_for_testing(&mut clock, current_time + (8 * ONE_HOUR_MILLIS) + 1); // 8+ hours

    // Check that total assets increased
    let total_assets = sdeusd::total_assets(&management, &clock);
    assert_eq(total_assets, initial_deposit + rewards);

    // Alice starts cooldown for half her position
    ts.next_tx(ALICE);
    let cooldown_assets = 500_000_000;
    sdeusd::cooldown_assets(
        &mut management,
        &global_config,
        cooldown_assets,
        &mut shares_coin,
        &clock,
        ts.ctx()
    );

    // Wait for cooldown to complete and unstake
    let cooldown_duration_in_ms = sdeusd::cooldown_duration(&management) * 1000;
    let new_time = clock::timestamp_ms(&clock) + cooldown_duration_in_ms + 1;
    clock::set_for_testing(&mut clock, new_time);

    sdeusd::unstake(
        &mut management,
        &global_config,
        ALICE,
        &clock,
        ts.ctx()
    );

    ts.next_tx(ALICE);
    let unstaked_coin = ts.take_from_address<Coin<DEUSD>>(ALICE);
    assert_eq(unstaked_coin.value(), cooldown_assets);

    shares_coin.burn_for_testing();
    unstaked_coin.burn_for_testing();
    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Helper Functions ===

public fun setup_test(): (test_scenario::Scenario, GlobalConfig, AdminCap, DeUSDConfig, SdeUSDManagement) {
    let mut ts = test_scenario::begin(ADMIN);
    let (global_config, admin_cap) = test_utils::setup_global_config(&mut ts, ADMIN);
    let deusd_config = test_utils::setup_deusd(&mut ts, ADMIN);
    let sdeusd_management = test_utils::setup_sdeusd(&mut ts, ADMIN);

    (ts, global_config, admin_cap, deusd_config, sdeusd_management)
}

public fun clean_test(
    ts: test_scenario::Scenario,
    global_config: GlobalConfig,
    admin_cap: AdminCap,
    deusd_config: DeUSDConfig,
    management: SdeUSDManagement,
) {
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(deusd_config);
    test_scenario::return_shared(management);
    admin_cap::destroy_for_test(admin_cap);
    ts.end();
}

public fun mint_deusd(deusd_config: &mut DeUSDConfig, amount: u64, ts: &mut test_scenario::Scenario): coin::Coin<DEUSD> {
    deusd::mint_for_test(deusd_config, amount, ts.ctx())
}