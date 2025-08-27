#[test_only]
module elixir::sdeusd_vesting_tests;

use elixir::deusd::DEUSD;
use elixir::test_utils;
use elixir::sdeusd_tests::{clean_test, setup_test, mint_deusd};
use elixir::sdeusd::{Self, SDEUSD};
use elixir::deusd;
use elixir::config;
use elixir::roles;
use sui::clock;
use sui::coin::Coin;
use sui::test_utils::assert_eq;

const ADMIN: address = @0xad;
const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;

const ONE_SECOND_MILLIS: u64 = 1000;
const ONE_HOUR_MILLIS: u64 = 3600 * 1000;
const VESTING_PERIOD_MILLIS: u64 = 8 * 3600 * 1000;

// === Vesting tests ===

#[test]
fun test_vesting_mechanism() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);

    // Grant rewarder role
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

    ts.next_tx(ADMIN);
    let rewards_coin = mint_deusd(&mut deusd_config, 100_000_000, &mut ts);
    sdeusd::transfer_in_rewards(
        &mut management,
        &global_config,
        rewards_coin,
        &clock,
        ts.ctx()
    );

    // Initially all rewards are unvested
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 100_000_000);
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets + 0);

    // After 4 hours (half vesting period), half should be vested
    let half_vesting_time = start_time + VESTING_PERIOD_MILLIS / 2;
    clock::set_for_testing(&mut clock, half_vesting_time);

    let unvested_half = sdeusd::get_unvested_amount(&management, &clock);
    let total_assets_half = sdeusd::total_assets(&management, &clock);

    // Should be 50 tokens unvested and 100 (initial) + 50 available
    assert_eq(unvested_half, 50_000_000);
    assert_eq(total_assets_half, initial_assets + 50_000_000);

    // After full vesting period (8 hours), all should be vested
    let full_vesting_time = start_time + VESTING_PERIOD_MILLIS;
    clock::set_for_testing(&mut clock, full_vesting_time);

    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets + 100_000_000);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unused_rewards_during_vesting() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // Set cooldown to 0 so we can test immediate withdrawals
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // ALICE deposits 1000 tokens
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    // Start rewards vesting: 800 tokens over 8 hours
    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Verify initial state: all rewards unvested, no unused rewards
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), rewards_amount);
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets);

    // Advance 4 hours (half vesting period)
    test_utils::advance_time(&mut clock, 4 * ONE_HOUR_MILLIS);

    // At 4 hours: 400 tokens vested, 400 tokens still vesting
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 400_000_000);
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);
    assert_eq(sdeusd::total_assets(&management, &clock), initial_assets + 400_000_000);

    // ALICE withdraws everything, bringing supply to zero
    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Verify supply is now zero
    assert_eq(sdeusd::total_supply(&management), 0);

    // After supply goes to zero, unused rewards should still be 0 because no time has passed
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);

    // Advance 2 more hours (6 hours total from start)
    test_utils::advance_time(&mut clock, 2 * ONE_HOUR_MILLIS);

    // Now unused rewards should show the amount accrued during zero-supply period
    // From hour 4 to hour 6 = 2 hours of unused rewards
    // 2/8 * 800 = 200 tokens unused
    let expected_unused = 200_000_000;
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), expected_unused);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unused_rewards_supply_returns_before_vesting_ends() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // ALICE deposits and rewards start vesting
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Advance 2 hours, then ALICE withdraws all (supply goes to zero)
    test_utils::advance_time(&mut clock, 2 * ONE_HOUR_MILLIS);

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Supply goes to zero at hour 2
    assert_eq(sdeusd::total_supply(&management), 0);

    // Advance to hour 6 (4 hours of zero supply)
    test_utils::advance_time(&mut clock, 4 * ONE_HOUR_MILLIS);

    // BOB deposits, bringing supply back above zero
    ts.next_tx(BOB);
    let bob_assets = 500_000_000;
    let bob_deusd_coin = mint_deusd(&mut deusd_config, bob_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd_coin, BOB, &clock, ts.ctx());

    // Now, supply = assets = 500_000_000 (no rewards added to assets yet)
    assert_eq(sdeusd::total_supply(&management), 500_000_000);

    // The unused reward amount should now reflect the 4 hours of zero supply
    // From hour 2 to hour 6 = 4 hours = 4/8 * 800 = 400 tokens unused
    let expected_unused = 400_000_000;
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), expected_unused);

    // Total assets calculation at hour 6:
    // Contract balance = BOB's 500 + remaining rewards 600 = 1100
    // Unvested rewards: (8-6)/8 * 800 = 200 tokens
    // Unused rewards: 4/8 * 800 = 400 tokens
    // Total assets = 1100 - 200 - 400 = 500 tokens (only BOB's deposit is available)
    assert_eq(sdeusd::total_assets(&management, &clock), 500_000_000);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unused_rewards_supply_returns_after_vesting_ends() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // ALICE deposits, rewards start vesting
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // ALICE withdraws at hour 3 (supply goes to zero)
    test_utils::advance_time(&mut clock, 3 * ONE_HOUR_MILLIS);

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // BOB deposits at hour 10 (after vesting period ended)
    test_utils::advance_time(&mut clock, 7 * ONE_HOUR_MILLIS);

    ts.next_tx(BOB);
    let bob_assets = 500_000_000;
    let bob_deusd_coin = mint_deusd(&mut deusd_config, bob_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd_coin, BOB, &clock, ts.ctx());

    // Unused rewards calculation:
    // Zero supply period: hour 3 to hour 8 (when vesting ended) = 5 hours
    // 5/8 * 800 = 500 tokens unused
    let expected_unused = 500_000_000;
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), expected_unused);

    // Since vesting ended, no more rewards are actively vesting
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);

    // Total assets should be: BOB's deposit only (all original rewards are unused)
    assert_eq(sdeusd::total_assets(&management, &clock), bob_assets);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unused_rewards_multiple_zero_supply_periods() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // Start first vesting period
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // First zero period: hours 2-4 (2 hours)
    clock::set_for_testing(&mut clock, start_time + (2 * ONE_HOUR_MILLIS));
    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // BOB deposits at hour 4, ending first zero period
    clock::set_for_testing(&mut clock, start_time + (4 * ONE_HOUR_MILLIS));
    ts.next_tx(BOB);
    let bob_deusd_coin = mint_deusd(&mut deusd_config, 500_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd_coin, BOB, &clock, ts.ctx());

    // Check unused rewards after first zero period
    // 2 hours unused: 2/8 * 800 = 200 tokens
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 200_000_000);

    // Second zero period: hours 5-7 (2 more hours)
    clock::set_for_testing(&mut clock, start_time + (5 * ONE_HOUR_MILLIS));
    ts.next_tx(BOB);
    let bob_shares = ts.take_from_address<Coin<SDEUSD>>(BOB);
    sdeusd::redeem(&mut management, &global_config, bob_shares, BOB, BOB, &clock, ts.ctx());

    // ALICE deposits again at hour 7, ending second zero period
    clock::set_for_testing(&mut clock, start_time + (7 * ONE_HOUR_MILLIS));
    ts.next_tx(ALICE);
    let alice_deusd_coin2 = mint_deusd(&mut deusd_config, 300_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, alice_deusd_coin2, ALICE, &clock, ts.ctx());

    // Check unused rewards after second zero period
    // First period: 2 hours = 200 tokens
    // Second period: 2 more hours = 200 more tokens
    // Total: 400 tokens unused
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 400_000_000);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unused_rewards_exactly_at_vesting_boundaries() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // Start vesting
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    ts.next_tx(ADMIN);
    let rewards_coin = mint_deusd(&mut deusd_config, 800_000_000, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Supply goes to zero exactly when vesting ends (hour 8)
    let vesting_end_time = start_time + (8 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, vesting_end_time);

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Since supply went to zero exactly at vesting end, no rewards should be unused
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);

    // Advance time and supply returns
    clock::set_for_testing(&mut clock, vesting_end_time + ONE_HOUR_MILLIS);
    ts.next_tx(BOB);
    let bob_deusd_coin = mint_deusd(&mut deusd_config, 500_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd_coin, BOB, &clock, ts.ctx());

    // Still no unused rewards since vesting was complete when supply went to zero
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unused_rewards_with_multiple_vesting_periods() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // First vesting period
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    ts.next_tx(ADMIN);
    let rewards_coin1 = mint_deusd(&mut deusd_config, 400_000_000, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin1, &clock, ts.ctx());

    // Supply goes to zero during first vesting period (hour 4)
    clock::set_for_testing(&mut clock, start_time + (4 * ONE_HOUR_MILLIS));
    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Wait for first vesting to complete while supply is zero
    clock::set_for_testing(&mut clock, start_time + (9 * ONE_HOUR_MILLIS));

    // Start second vesting period while supply is still zero
    ts.next_tx(ADMIN);
    let rewards_coin2 = mint_deusd(&mut deusd_config, 600_000_000, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin2, &clock, ts.ctx());

    // Supply returns during second vesting period (hour 11)
    clock::set_for_testing(&mut clock, start_time + (11 * ONE_HOUR_MILLIS));
    ts.next_tx(BOB);
    let bob_deusd_coin = mint_deusd(&mut deusd_config, 500_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd_coin, BOB, &clock, ts.ctx());

    // Calculate expected unused rewards:
    // First period: went to zero at hour 4, vesting ended at hour 8
    // Unused from first period: (8-4)/8 * 400 = 200 tokens
    // Second period: started at hour 9, supply returned at hour 11
    // Unused from second period: (11-9)/8 * 600 = 150 tokens
    // Total unused: 200 + 150 = 350 tokens
    let expected_unused = 350_000_000;
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), expected_unused);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_get_unused_reward_amount_consistency() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // Setup vesting
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    ts.next_tx(ADMIN);
    let rewards_coin = mint_deusd(&mut deusd_config, 800_000_000, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Supply goes to zero at hour 3
    clock::set_for_testing(&mut clock, start_time + (3 * ONE_HOUR_MILLIS));
    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Call get_unused_reward_amount multiple times during zero supply period
    // Values should be consistent and increasing with time
    let unused_at_hour_3 = sdeusd::get_total_unused_reward_amount(&management, &clock);

    clock::set_for_testing(&mut clock, start_time + (5 * ONE_HOUR_MILLIS));
    let unused_at_hour_5 = sdeusd::get_total_unused_reward_amount(&management, &clock);

    clock::set_for_testing(&mut clock, start_time + (7 * ONE_HOUR_MILLIS));
    let unused_at_hour_7 = sdeusd::get_total_unused_reward_amount(&management, &clock);

    // Unused rewards should increase as time progresses during zero supply
    assert!(unused_at_hour_5 > unused_at_hour_3);
    assert!(unused_at_hour_7 > unused_at_hour_5);

    // Expected values:
    // Hour 3: 0 unused (just went to zero)
    // Hour 5: 2/8 * 800 = 200 unused
    // Hour 7: 4/8 * 800 = 400 unused
    assert_eq(unused_at_hour_3, 0);
    assert_eq(unused_at_hour_5, 200_000_000);
    assert_eq(unused_at_hour_7, 400_000_000);

    // Supply returns at hour 7
    ts.next_tx(BOB);
    let bob_deusd_coin = mint_deusd(&mut deusd_config, 500_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd_coin, BOB, &clock, ts.ctx());

    // After supply returns, unused amount should be stable (committed to state)
    let unused_after_return = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_after_return, 400_000_000);

    // Advance time and check that unused amount doesn't change anymore
    clock::set_for_testing(&mut clock, start_time + (10 * ONE_HOUR_MILLIS));
    let unused_later = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_later, 400_000_000); // Should remain the same

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_initial_state_and_first_zero_supply_transition() {
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

    // Verify initial state is correct
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);
    assert_eq(sdeusd::total_supply(&management), 1000_000_000);

    // Start rewards while supply is present
    ts.next_tx(ADMIN);
    let rewards_coin = mint_deusd(&mut deusd_config, 400_000_000, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Advance time
    clock::set_for_testing(&mut clock, start_time + (4 * ONE_HOUR_MILLIS));

    // Since supply has never gone to zero, no unused rewards should be calculated
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);

    // Normal vesting should continue
    let remaining_unvested = 200_000_000; // 4/8 * 400 remaining
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), remaining_unvested);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_zero_supply_at_exact_vesting_start() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // User deposits
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    // Start vesting
    ts.next_tx(ADMIN);
    let rewards_coin = mint_deusd(&mut deusd_config, 800_000_000, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Supply goes to zero immediately at vesting start (same timestamp)
    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Advance time
    clock::set_for_testing(&mut clock, start_time + (4 * ONE_HOUR_MILLIS));

    // All time since vesting start should count as unused
    let expected_unused = 400_000_000; // 4/8 * 800
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), expected_unused);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_unused_rewards_calculation_precision() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // Start with precise amounts for testing
    ts.next_tx(ALICE);
    let deusd_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    ts.next_tx(ADMIN);
    let rewards_amount = 777_777_777; // Odd number to test precision
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Supply goes to zero at 1.5 hours (1.5 * 3600 * 1000 = 5,400,000 ms)
    clock::set_for_testing(&mut clock, start_time + (5400 * 1000));
    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Supply returns at 3.7 hours (3.7 * 3600 * 1000 = 13,320,000 ms)
    clock::set_for_testing(&mut clock, start_time + (13320 * 1000));
    ts.next_tx(BOB);
    let bob_deusd_coin = mint_deusd(&mut deusd_config, 500_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd_coin, BOB, &clock, ts.ctx());

    // Zero period was 2.2 hours = 2.2/8 * 777,777,777 = 213,888,888.425...
    // Should be rounded down to 213,888,888
    let expected_unused = 213_888_888;
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), expected_unused);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}


#[test]
fun test_vesting_zero_supply_cooldown() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // Keep cooldown duration > 0 (2 hours in seconds)
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 2 * 3600); // 2 hours

    // Start vesting with no supply (zero stakers)
    ts.next_tx(ADMIN);
    let rewards_coin = mint_deusd(&mut deusd_config, 400_000_000, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Verify initial state
    let unused_initial = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_initial, 0); // No time passed yet
    let unvested_initial = sdeusd::get_unvested_amount(&management, &clock);
    assert_eq(unvested_initial, 400_000_000);

    // Move to 2 hours (25% of vesting period) - still zero supply
    clock::set_for_testing(&mut clock, start_time + (2 * ONE_HOUR_MILLIS));
    let unused_early = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_early, 100_000_000); // 25% of rewards are now unused due to zero supply

    // User deposits during vesting period
    ts.next_tx(ALICE);
    let deposit_coin = mint_deusd(&mut deusd_config, 1000_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deposit_coin, ALICE, &clock, ts.ctx());

    // Move to 4 hours (50% of vesting period) with Alice having supply
    clock::set_for_testing(&mut clock, start_time + (4 * ONE_HOUR_MILLIS));
    let unused_mid = sdeusd::get_total_unused_reward_amount(&management, &clock);
    // From 0-2 hours: 100 unused (zero supply)
    // From 2-4 hours: rewards distributed to Alice (no additional unused)
    assert_eq(unused_mid, 100_000_000);

    // Alice initiates cooldown for all her shares, which moves them to silo (effectively zero supply)
    ts.next_tx(ALICE);
    let mut alice_shares = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::cooldown_shares(&mut management, &global_config, &mut alice_shares, &clock, ts.ctx());
    alice_shares.burn_for_testing(); // Should be empty now

    // Move to 6 hours (75% of vesting period) - zero supply again due to cooldown
    clock::set_for_testing(&mut clock, start_time + (6 * ONE_HOUR_MILLIS));
    let unused_late = sdeusd::get_total_unused_reward_amount(&management, &clock);
    // From 0-2 hours: 100 unused (zero supply)
    // From 2-4 hours: 0 unused (Alice had supply)
    // From 4-6 hours: 100 unused (zero supply due to cooldown)
    // Total: 200M unused
    assert_eq(unused_late, 200_000_000);

    // Complete vesting (8 hours total)
    clock::set_for_testing(&mut clock, start_time + (8 * ONE_HOUR_MILLIS + ONE_SECOND_MILLIS));

    // Check final unused rewards
    let unused_final = sdeusd::get_total_unused_reward_amount(&management, &clock);
    // From 0-2 hours: 100 unused (zero supply)
    // From 2-4 hours: 0 unused (Alice had supply)
    // From 4-8 hours: 200 unused (zero supply due to cooldown)
    // Total: 300 unused out of 400M total
    assert_eq(unused_final, 300_000_000);

    let unvested_final = sdeusd::get_unvested_amount(&management, &clock);
    assert_eq(unvested_final, 0); // All should be vested now

    // Unstake after cooldown period
    clock::set_for_testing(&mut clock, start_time + (12 * ONE_HOUR_MILLIS));
    ts.next_tx(ALICE);
    sdeusd::unstake(&mut management, &global_config, ALICE, &clock, ts.ctx());

    // Withdraw unused rewards
    ts.next_tx(ADMIN);
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, ADMIN, &clock, ts.ctx());

    ts.next_tx(ADMIN);
    let unused_rewards = ts.take_from_address<Coin<DEUSD>>(ADMIN);
    assert_eq(unused_rewards.value(), 300_000_000);
    unused_rewards.burn_for_testing();

    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Withdraw Unused Rewards Tests ===

#[test]
fun test_withdraw_unused_rewards() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // Set cooldown to 0 for easier testing
    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // ALICE deposits 1000 tokens
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    // Start rewards vesting: 800 tokens over 8 hours
    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Advance 4 hours and ALICE withdraws everything (supply goes to zero)
    let mid_vesting_time = start_time + (4 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, mid_vesting_time);

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Complete vesting period
    let end_vesting_time = start_time + VESTING_PERIOD_MILLIS + ONE_SECOND_MILLIS;
    clock::set_for_testing(&mut clock, end_vesting_time);

    // Check unused rewards calculation
    let expected_unused = 400_000_000; // 4 hours of rewards during zero supply
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), expected_unused);

    // Withdraw unused rewards
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, BOB, &clock, ts.ctx());

    // Verify state was updated correctly
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);
    assert_eq(sdeusd::total_assets(&management, &clock), 0);
    assert_eq(sdeusd::total_supply(&management), 0);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = elixir::sdeusd::EZeroAmount)]
fun test_withdraw_unused_rewards_fails_when_zero_unused() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // Try to withdraw when there are no unused rewards
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, ADMIN, &clock, ts.ctx());

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_withdraw_unused_rewards_during_active_vesting() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // ALICE deposits
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    // Start rewards vesting
    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Supply goes to zero for 2 hours
    let zero_supply_start = start_time + (2 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, zero_supply_start);

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    let zero_supply_end = zero_supply_start + (2 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, zero_supply_end);

    // Supply returns (BOB deposits) - this triggers unused reward accumulation
    ts.next_tx(BOB);
    let bob_assets = 500_000_000;
    let bob_deusd = mint_deusd(&mut deusd_config, bob_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd, BOB, &clock, ts.ctx());

    // After supply returns, unused rewards should be accumulated in total_unused_reward_amount
    let expected_unused = 200_000_000; // 2 hours of zero supply
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), expected_unused);

    // Advance time but vesting is still active
    let current_time = zero_supply_end + ONE_HOUR_MILLIS; // 5 hours total, still within 8-hour vesting
    clock::set_for_testing(&mut clock, current_time);

    // Withdraw unused rewards during active vesting
    ts.next_tx(ADMIN);
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, BOB, &clock, ts.ctx());

    // Verify: unused rewards withdrawn, but vesting continues normally
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);
    assert!(sdeusd::get_unvested_amount(&management, &clock) > 0); // Still vesting

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = elixir::sdeusd::EZeroAmount)]
fun test_withdraw_unused_rewards_exactly_at_vesting_completion() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // ALICE deposits
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    // Start rewards vesting
    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Supply goes to zero at 6 hours
    let zero_supply_time = start_time + (6 * ONE_HOUR_MILLIS);
    clock::set_for_testing(&mut clock, zero_supply_time);

    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Advance exactly to vesting completion
    let vesting_end_time = start_time + VESTING_PERIOD_MILLIS;
    clock::set_for_testing(&mut clock, vesting_end_time);

    // Withdraw unused rewards exactly at vesting completion, should fail as unused is zero
    // because we don't finalize unused rewards until at this point.
    ts.next_tx(ADMIN);
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, ADMIN, &clock, ts.ctx());

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_withdraw_unused_rewards_multiple_zero_supply_periods() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // ALICE deposits
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    // Start rewards vesting
    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // First zero supply period: 1-2 hours
    clock::set_for_testing(&mut clock, start_time + ONE_HOUR_MILLIS);
    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Supply returns at 2 hours
    clock::set_for_testing(&mut clock, start_time + (2 * ONE_HOUR_MILLIS));
    ts.next_tx(BOB);
    let bob_deusd = mint_deusd(&mut deusd_config, 500_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd, BOB, &clock, ts.ctx());

    // Second zero supply period: 4-6 hours
    clock::set_for_testing(&mut clock, start_time + (4 * ONE_HOUR_MILLIS));
    ts.next_tx(BOB);
    let bob_shares = ts.take_from_address<Coin<SDEUSD>>(BOB);
    sdeusd::redeem(&mut management, &global_config, bob_shares, BOB, BOB, &clock, ts.ctx());

    // Complete vesting
    clock::set_for_testing(&mut clock, start_time + VESTING_PERIOD_MILLIS + ONE_SECOND_MILLIS);

    // Expected unused: 1 hour (1-2h) + 2 hours (4-6h) + 2 hours (6-8h) = 5 hours = 500 tokens
    let expected_unused = 500_000_000;
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), expected_unused);

    // Withdraw unused rewards
    ts.next_tx(ADMIN);
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, ADMIN, &clock, ts.ctx());

    // Verify complete cleanup
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_withdraw_unused_rewards_state_consistency() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // ALICE deposits
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    // Start rewards vesting
    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Supply goes to zero for 3 hours
    clock::set_for_testing(&mut clock, start_time + (2 * ONE_HOUR_MILLIS));
    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    clock::set_for_testing(&mut clock, start_time + (5 * ONE_HOUR_MILLIS));

    // To get unused rewards into total_unused_reward_amount, we need supply to return
    ts.next_tx(BOB);
    let bob_deusd = mint_deusd(&mut deusd_config, 500_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd, BOB, &clock, ts.ctx());

    // Now unused rewards should be in total_unused_reward_amount
    let unused_rewards_before = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_rewards_before, 300_000_000); // Should have accumulated unused rewards

    // Get total assets before withdrawal
    let total_assets_before = sdeusd::total_assets(&management, &clock);

    // Withdraw unused rewards
    ts.next_tx(ADMIN);
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, BOB, &clock, ts.ctx());

    // Verify total_assets not changed after withdrawal
    let total_assets_after = sdeusd::total_assets(&management, &clock);
    assert_eq(total_assets_after, total_assets_before);

    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_withdraw_unused_rewards_edge_timing() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // ALICE deposits
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    // Start rewards vesting
    ts.next_tx(ADMIN);
    let rewards_amount = 800_000_000;
    let rewards_coin = mint_deusd(&mut deusd_config, rewards_amount, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin, &clock, ts.ctx());

    // Supply goes to zero exactly at vesting start
    clock::set_for_testing(&mut clock, start_time);
    ts.next_tx(ALICE);
    let shares_coin = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin, ALICE, ALICE, &clock, ts.ctx());

    // Supply returns exactly at vesting end
    clock::set_for_testing(&mut clock, start_time + VESTING_PERIOD_MILLIS);
    ts.next_tx(BOB);
    let bob_deusd = mint_deusd(&mut deusd_config, 500_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd, BOB, &clock, ts.ctx());

    // All rewards should be unused (entire vesting period was zero supply)
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), rewards_amount);

    // Withdraw unused rewards
    ts.next_tx(ADMIN);
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, ADMIN, &clock, ts.ctx());

    // Verify complete cleanup
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}


#[test]
fun test_withdraw_unused_rewards_sequential_vesting_periods() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    sdeusd::set_cooldown_duration(&admin_cap, &mut management, &global_config, 0);

    // First Vesting Period (Hours 0-8)
    // Initial deposit
    ts.next_tx(ALICE);
    let initial_assets = 1000_000_000;
    let deusd_coin = mint_deusd(&mut deusd_config, initial_assets, &mut ts);
    sdeusd::deposit(&mut management, &global_config, deusd_coin, ALICE, &clock, ts.ctx());

    // Start first vesting: 400 tokens over 8 hours
    ts.next_tx(ADMIN);
    let first_rewards = 400_000_000;
    let rewards_coin1 = mint_deusd(&mut deusd_config, first_rewards, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin1, &clock, ts.ctx());

    // Zero supply period: hours 2-4 (2 hours)
    clock::set_for_testing(&mut clock, start_time + (2 * ONE_HOUR_MILLIS));
    ts.next_tx(ALICE);
    let shares_coin1 = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, shares_coin1, ALICE, ALICE, &clock, ts.ctx());

    clock::set_for_testing(&mut clock, start_time + (4 * ONE_HOUR_MILLIS));
    ts.next_tx(BOB);
    let bob_deusd1 = mint_deusd(&mut deusd_config, 500_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd1, BOB, &clock, ts.ctx());

    // Check unused rewards: 2/8 * 400 = 100 tokens
    let unused_after_first_zero = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_after_first_zero, 100_000_000);

    // Wait for first vesting to complete
    clock::set_for_testing(&mut clock, start_time + (8 * ONE_HOUR_MILLIS + ONE_SECOND_MILLIS));
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);

    // Withdraw first batch of unused rewards
    ts.next_tx(ADMIN);
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, ADMIN, &clock, ts.ctx());
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);

    // Second vesting period (Hours 8-16) ===
    // Start second vesting: 600 tokens over 8 hours
    ts.next_tx(ADMIN);
    let second_rewards = 600_000_000;
    let rewards_coin2 = mint_deusd(&mut deusd_config, second_rewards, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin2, &clock, ts.ctx());

    // Zero supply period: hours 10-13 (3 hours)
    clock::set_for_testing(&mut clock, start_time + (10 * ONE_HOUR_MILLIS));
    ts.next_tx(BOB);
    let bob_shares1 = ts.take_from_address<Coin<SDEUSD>>(BOB);
    sdeusd::redeem(&mut management, &global_config, bob_shares1, BOB, BOB, &clock, ts.ctx());

    clock::set_for_testing(&mut clock, start_time + (13 * ONE_HOUR_MILLIS));
    ts.next_tx(ALICE);
    let alice_deusd2 = mint_deusd(&mut deusd_config, 700_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, alice_deusd2, ALICE, &clock, ts.ctx());

    // Check unused rewards: 3/8 * 600 = 225 tokens
    let unused_after_second_zero = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_after_second_zero, 225_000_000);

    // Wait for second vesting to complete
    clock::set_for_testing(&mut clock, start_time + (16 * ONE_HOUR_MILLIS + ONE_SECOND_MILLIS));
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);

    // Withdraw second batch of unused rewards
    ts.next_tx(ADMIN);
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, ADMIN, &clock, ts.ctx());
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);

    // Third vesting period
    // Start third vesting: 800 tokens over 8 hours
    ts.next_tx(ADMIN);
    let third_rewards = 800_000_000;
    let rewards_coin3 = mint_deusd(&mut deusd_config, third_rewards, &mut ts);
    sdeusd::transfer_in_rewards(&mut management, &global_config, rewards_coin3, &clock, ts.ctx());

    // Zero supply period: hours 18-21 (3 hours)
    clock::set_for_testing(&mut clock, start_time + (18 * ONE_HOUR_MILLIS));
    ts.next_tx(ALICE);
    let alice_shares2 = ts.take_from_address<Coin<SDEUSD>>(ALICE);
    sdeusd::redeem(&mut management, &global_config, alice_shares2, ALICE, ALICE, &clock, ts.ctx());

    clock::set_for_testing(&mut clock, start_time + (21 * ONE_HOUR_MILLIS));
    ts.next_tx(BOB);
    let bob_deusd2 = mint_deusd(&mut deusd_config, 600_000_000, &mut ts);
    sdeusd::deposit(&mut management, &global_config, bob_deusd2, BOB, &clock, ts.ctx());

    // Check unused rewards: 3/8 * 800 = 300 tokens
    let unused_after_third_zero = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_after_third_zero, 300_000_000);

    // Complete third vesting
    clock::set_for_testing(&mut clock, start_time + (24 * ONE_HOUR_MILLIS + ONE_SECOND_MILLIS));
    assert_eq(sdeusd::get_unvested_amount(&management, &clock), 0);

    // Final withdrawal
    ts.next_tx(ADMIN);
    sdeusd::withdraw_unused_rewards(&admin_cap, &mut management, &global_config, ADMIN, &clock, ts.ctx());
    assert_eq(sdeusd::get_total_unused_reward_amount(&management, &clock), 0);

    // Total withdrawn across all periods: 100 + 225 + 300 = 625 tokens
    // This represents the rewards that were unused due to zero supply periods
    ts.next_tx(ADMIN);
    let unused_rewards_1 = ts.take_from_address<Coin<DEUSD>>(ADMIN);
    let unused_rewards_2 = ts.take_from_address<Coin<DEUSD>>(ADMIN);
    let unused_rewards_3 = ts.take_from_address<Coin<DEUSD>>(ADMIN);

    let total_unused = unused_rewards_1.value() + unused_rewards_2.value() + unused_rewards_3.value();
    assert_eq(total_unused, 625_000_000);

    unused_rewards_1.burn_for_testing();
    unused_rewards_2.burn_for_testing();
    unused_rewards_3.burn_for_testing();

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_get_total_unused_reward_amount() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

    ts.next_tx(ADMIN);
    config::add_role(&admin_cap, &mut global_config, ADMIN, roles::role_rewarder());

    let mut clock = clock::create_for_testing(ts.ctx());
    let start_time = 1000000;
    clock::set_for_testing(&mut clock, start_time);

    // Add rewards and immediately check
    ts.next_tx(ADMIN);
    let reward_amount = 800000;
    let reward_coin = deusd::mint_for_test(&mut deusd_config, reward_amount, ts.ctx());
    sdeusd::transfer_in_rewards(&mut management, &global_config, reward_coin, &clock, ts.ctx());

    let unused_at_start = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_at_start, 0); // No time has passed yet

    // 2 hours after vesting started (25% of vesting period)
    clock::set_for_testing(&mut clock, start_time + 2 * ONE_HOUR_MILLIS);
    let unused_after_2h = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_after_2h, 200000);

    // 4 hours after vesting started (50% of vesting period)
    clock::set_for_testing(&mut clock, start_time + 4 * ONE_HOUR_MILLIS);
    let unused_after_4h = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_after_4h, 400000);

    // 8 hours after vesting started (100% of vesting period)
    clock::set_for_testing(&mut clock, start_time + 8 * ONE_HOUR_MILLIS);
    let unused_after_8h = sdeusd::get_total_unused_reward_amount(&management, &clock);
    assert_eq(unused_after_8h, 800000);

    clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}
