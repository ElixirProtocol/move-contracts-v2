#[test_only]
module elixir::deusd_lp_staking_tests;

use sui::clock;
use sui::coin;
use sui::test_scenario;
use elixir::admin_cap::{Self, AdminCap};
use elixir::config::{Self, GlobalConfig};
use elixir::deusd_lp_staking::{Self, DeUSDLPStakingManagement};
use sui::test_utils::assert_eq;

// Test coin types
public struct TestCoin has drop {}
public struct TestCoin2 has drop {}

// Test user addresses
const BOB1: address = @0xB0B1;
const BOB2: address = @0xB0B2;
const BOB3: address = @0xB0B3;

// === Initialization and Configuration Tests ===

#[test]
fun test_initialization() {
    let mut ts = test_scenario::begin(@elixir);

    let admin_cap = admin_cap::create_for_test(ts.ctx());
    let global_config = config::create_for_test(ts.ctx());

    deusd_lp_staking::init_for_test(ts.ctx());

    ts.next_tx(@elixir);
    let mut staking_management = ts.take_shared<DeUSDLPStakingManagement>();

    assert_eq(deusd_lp_staking::get_current_epoch(&staking_management), 0);

    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    assert_eq(deusd_lp_staking::get_current_epoch(&staking_management), 1);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    test_scenario::return_shared(staking_management);

    ts.end();
}

#[test]
fun test_update_stake_parameters() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);

    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    let epoch = 1u8;
    let stake_limit = 1000u64;
    let cooldown = 86400u64; // 1 day

    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        epoch,
        stake_limit,
        cooldown,
    );

    // Verify parameters
    let (param_epoch, param_stake_limit, param_cooldown, total_staked, total_cooling_down) =
        deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);

    assert_eq(param_epoch, epoch);
    assert_eq(param_stake_limit, stake_limit);
    assert_eq(param_cooldown, cooldown);
    assert_eq(total_staked, 0);
    assert_eq(total_cooling_down, 0);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
fun test_update_existing_stake_parameters() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set initial parameters
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // Update parameters
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        2, 2000, 172800, // New values
    );

    // Verify updated parameters
    let (epoch, stake_limit, cooldown, total_staked, total_cooling_down) =
        deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);

    assert_eq(epoch, 2);
    assert_eq(stake_limit, 2000);
    assert_eq(cooldown, 172800);
    assert_eq(total_staked, 0); // Should remain unchanged
    assert_eq(total_cooling_down, 0); // Should remain unchanged

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
fun test_cooldown_period_at_max() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set cooldown period exactly at max (should succeed)
    let max_cooldown = 90 * 24 * 60 * 60; // 90 days in seconds
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1,
        1000,
        max_cooldown,
    );

    // Verify parameters
    let (_, _, cooldown, _, _) = deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);
    assert_eq(cooldown, max_cooldown);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EMaxCooldownExceeded)]
fun test_update_stake_parameters_fail_if_cooldown_period_too_long() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Try to set cooldown period longer than max (90 days)
    let max_cooldown = 90 * 24 * 60 * 60; // 90 days in seconds
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1,
        1000,
        max_cooldown + 1, // One second over the limit
    );

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvalidEpoch)]
fun test_set_same_epoch() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Try to set the same epoch - should fail
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 0);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

// === Staking Tests ===

#[test]
fun test_stake_tokens() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);

    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set up stake parameters
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1,
        1000,
        86400,
    );

    // Create test coins for user
    let test_coin = coin::mint_for_testing<TestCoin>(100, &mut ctx);

    // Stake tokens
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin, &mut ctx);

    // Verify stake data
    let (staked_amount, cooling_down_amount, cooldown_start) =
        deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, tx_context::sender(&ctx));

    assert_eq(staked_amount, 100);
    assert_eq(cooling_down_amount, 0);
    assert_eq(cooldown_start, 0);

    // Verify contract balance
    assert_eq(deusd_lp_staking::get_balance<TestCoin>(&staking_management), 100);

    // Verify total staked updated
    let (_, _, _, total_staked, total_cooling_down) =
        deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);
    assert_eq(total_staked, 100);
    assert_eq(total_cooling_down, 0);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
fun test_multiple_stakes_same_user() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set up stake parameters
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // First stake
    let test_coin1 = coin::mint_for_testing<TestCoin>(50, &mut ctx);
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin1, &mut ctx);

    // Second stake (should accumulate)
    let test_coin2 = coin::mint_for_testing<TestCoin>(30, &mut ctx);
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin2, &mut ctx);

    // Verify accumulated stake
    let (staked_amount, cooling_down_amount, _) =
        deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, tx_context::sender(&ctx));

    assert_eq(staked_amount, 80); // 50 + 30
    assert_eq(cooling_down_amount, 0);

    // Verify contract balance
    assert_eq(deusd_lp_staking::get_balance<TestCoin>(&staking_management), 80);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
fun test_multiple_token_types() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);

    // Set up parameters for both token types
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    deusd_lp_staking::update_stake_parameters<TestCoin2>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 500, 43200, // Different parameters
    );

    // Stake both token types
    let test_coin1 = coin::mint_for_testing<TestCoin>(100, &mut ctx);
    let test_coin2 = coin::mint_for_testing<TestCoin2>(50, &mut ctx);

    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin1, &mut ctx);
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin2, &mut ctx);

    // Verify separate balances
    assert_eq(deusd_lp_staking::get_balance<TestCoin>(&staking_management), 100);
    assert_eq(deusd_lp_staking::get_balance<TestCoin2>(&staking_management), 50);

    // Verify separate stake data
    let (staked1, _, _) = deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, tx_context::sender(&ctx));
    let (staked2, _, _) = deusd_lp_staking::get_stake_data<TestCoin2>(&staking_management, tx_context::sender(&ctx));

    assert_eq(staked1, 100);
    assert_eq(staked2, 50);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

// === Staking Validation Tests ===

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvalidAmount)]
fun test_stake_zero_amount() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set up stake parameters
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // Try to stake zero amount
    let test_coin = coin::mint_for_testing<TestCoin>(0, &mut ctx);
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EStakeLimitExceeded)]
fun test_stake_limit_exceeded() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set up stake parameters with low limit
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 50, 86400,
    );

    // Try to stake more than limit
    let test_coin = coin::mint_for_testing<TestCoin>(100, &mut ctx);
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvalidEpoch)]
fun test_stake_wrong_epoch() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set current epoch to 1, but stake parameters for epoch 2
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        2,
        1000,
        86400,
    );

    // Current epoch is still 1, so staking should fail
    let test_coin = coin::mint_for_testing<TestCoin>(100, &mut ctx);
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::ENoStakeParameters)]
fun test_stake_unsupported_token() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);

    // Don't set stake parameters for TestCoin, so it's unsupported
    let test_coin = coin::mint_for_testing<TestCoin>(100, &mut ctx);
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

// === Unstaking Tests ===

#[test]
fun test_unstake_tokens() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let clock_obj = clock::create_for_testing(&mut ctx);

    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Unstake 50 tokens
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 60, &clock_obj, &mut ctx);

    // Verify stake data
    let (staked_amount, cooling_down_amount, cooldown_start) =
        deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, tx_context::sender(&ctx));

    assert_eq(staked_amount, 40); // 100 - 60
    assert_eq(cooling_down_amount, 60);
    assert_eq(cooldown_start, 0); // Clock starts at 0

    // Verify totals updated
    let (_, _, _, total_staked, total_cooling_down) =
        deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);
    assert_eq(total_staked, 40);
    assert_eq(total_cooling_down, 60);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
fun test_partial_unstake_and_withdraw() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Unstake only part of the stake (30 out of 100)
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 30, &clock_obj, &mut ctx);

    // Verify state after partial unstake
    let (staked_amount, cooling_down_amount, _) =
        deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, tx_context::sender(&ctx));
    assert_eq(staked_amount, 70); // 100 - 30
    assert_eq(cooling_down_amount, 30);

    // Advance clock past cooldown
    clock::increment_for_testing(&mut clock_obj, 86401 * 1000); // 1 day + 1 second

    // Withdraw only part of cooling down tokens (20 out of 30)
    deusd_lp_staking::withdraw<TestCoin>(&mut staking_management, &global_config, 20, &clock_obj, &mut ctx);

    // Verify final state
    let (final_staked, final_cooling_down, _) =
        deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, tx_context::sender(&ctx));
    assert_eq(final_staked, 70);
    assert_eq(final_cooling_down, 10); // 30 - 20

    // Verify contract balance decreased
    assert_eq(deusd_lp_staking::get_balance<TestCoin>(&staking_management), 80); // 100 - 20

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
fun test_multiple_unstake_operations() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // First unstake
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 30, &clock_obj, &mut ctx);

    // Advance time a bit but not past cooldown
    clock::increment_for_testing(&mut clock_obj, 1000);

    // Second unstake (should update cooldown start time)
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 20, &clock_obj, &mut ctx);

    // Verify accumulated cooling down amount
    let (staked_amount, cooling_down_amount, cooldown_start) =
        deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, tx_context::sender(&ctx));

    assert_eq(staked_amount, 50); // 100 - 30 - 20
    assert_eq(cooling_down_amount, 50); // 30 + 20
    assert_eq(cooldown_start, 1); // Should be updated to latest unstake time

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvalidAmount)]
fun test_unstake_zero_amount() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Try to unstake zero amount
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 0, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvalidAmount)]
fun test_unstake_more_than_staked() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Try to unstake more than staked (staked 100, trying to unstake 150)
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 150, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::ENoUserStake)]
fun test_unstake_no_stake_data() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set up parameters but don't stake anything
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // Try to unstake without having any stake
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::ENoUserStake)]
fun test_unstake_no_stake_data_for_token() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Try to unstake without having any stake
    deusd_lp_staking::unstake<TestCoin2>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

// === Withdrawal Tests ===

#[test]
fun test_withdraw_tokens() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut clock_obj = clock::create_for_testing(&mut ctx);

    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Unstake tokens
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    // Advance clock past cooldown period (1 day = 86400 seconds)
    clock::increment_for_testing(&mut clock_obj, 86401 * 1000); // Convert to milliseconds

    // Withdraw tokens
    deusd_lp_staking::withdraw<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    // Verify stake data
    let (staked_amount, cooling_down_amount, _) =
        deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, tx_context::sender(&ctx));

    assert_eq(staked_amount, 50);
    assert_eq(cooling_down_amount, 0); // Withdrawn

    // Verify totals updated
    let (_, _, _, total_staked, total_cooling_down) =
        deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);
    assert_eq(total_staked, 50);
    assert_eq(total_cooling_down, 0);

    // Verify contract balance decreased
    assert_eq(deusd_lp_staking::get_balance<TestCoin>(&staking_management), 50);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

// === Withdrawal Validation Tests ===

#[test]
#[expected_failure(abort_code = deusd_lp_staking::ECooldownNotOver)]
fun test_withdraw_before_cooldown() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let clock_obj = clock::create_for_testing(&mut ctx);

    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Unstake tokens
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    // Try to withdraw immediately (before cooldown)
    deusd_lp_staking::withdraw<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvalidAmount)]
fun test_withdraw_zero_amount() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Unstake some tokens first
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    // Advance clock past cooldown
    clock::increment_for_testing(&mut clock_obj, 86401 * 1000);

    // Try to withdraw zero amount
    deusd_lp_staking::withdraw<TestCoin>(&mut staking_management, &global_config, 0, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvalidAmount)]
fun test_withdraw_more_than_cooling_down() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Unstake 50 tokens
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    // Advance clock past cooldown
    clock::increment_for_testing(&mut clock_obj, 86401 * 1000);

    // Try to withdraw more than cooling down (cooling down 50, trying to withdraw 51)
    deusd_lp_staking::withdraw<TestCoin>(&mut staking_management, &global_config, 51, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvalidAmount)]
fun test_withdraw_no_cooling_down_tokens() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Try to withdraw without unstaking first (no cooling down tokens)
    deusd_lp_staking::withdraw<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::ENoUserStake)]
fun test_withdraw_no_stake_data() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set up parameters but don't stake anything
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // Try to withdraw without having any stake data for any user
    deusd_lp_staking::withdraw<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::ENoUserStake)]
fun test_withdraw_no_stake_data_for_token() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let clock_obj = clock::create_for_testing(&mut ctx);
    let mut staking_management = setup_staking_with_stake(&admin_cap, &global_config, &mut ctx);

    // Try to withdraw for a token type that the user hasn't staked (TestCoin2)
    // The user has staked TestCoin but not TestCoin2
    deusd_lp_staking::withdraw<TestCoin2>(&mut staking_management, &global_config, 50, &clock_obj, &mut ctx);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
}

// === Query Function Tests ===

#[test]
fun test_get_stake_data_nonexistent_user() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Get stake data for a user that doesn't exist
    let (staked_amount, cooling_down_amount, cooldown_start) =
        deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, @0x123);

    assert_eq(staked_amount, 0);
    assert_eq(cooling_down_amount, 0);
    assert_eq(cooldown_start, 0);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
fun test_get_stake_parameters_nonexistent_token() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Get parameters for a token that doesn't have parameters set
    let (epoch, stake_limit, cooldown, total_staked, total_cooling_down) =
        deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);

    assert_eq(epoch, 0);
    assert_eq(stake_limit, 0);
    assert_eq(cooldown, 0);
    assert_eq(total_staked, 0);
    assert_eq(total_cooling_down, 0);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
fun test_get_balance_no_tokens() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Get balance when no tokens have been staked
    let balance = deusd_lp_staking::get_balance<TestCoin>(&staking_management);
    assert_eq(balance, 0);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
fun test_get_balance_has_tokens() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set up stake parameters and stake tokens
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // Stake tokens to create a balance store
    let test_coin = coin::mint_for_testing<TestCoin>(100, &mut ctx);
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin, &mut ctx);

    // Verify that balance store now exists and has the correct amount
    let balance = deusd_lp_staking::get_balance<TestCoin>(&staking_management);
    assert_eq(balance, 100);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

// === Invariant Tests ===

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvariantBroken)]
fun test_invariant_broken_no_balance_store() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set up stake parameters
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // Artificially set totals to create invariant violation
    // No balance store exists (contract_balance = 0) but totals > 0
    deusd_lp_staking::update_stake_parameters_for_test<TestCoin>(
        &mut staking_management,
        100,
        50,
    );

    // This should abort with error EInvariantBroken: 0 < (100 + 50)
    deusd_lp_staking::run_invariant_check_for_test<TestCoin>(&staking_management);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EInvariantBroken)]
fun test_invariant_broken_insufficient_balance() {
    let mut ctx = tx_context::dummy();

    let admin_cap = admin_cap::create_for_test(&mut ctx);
    let global_config = config::create_for_test(&mut ctx);
    let mut staking_management = deusd_lp_staking::create_for_test(&mut ctx);

    // Set up stake parameters and stake some tokens to create balance store
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // Stake tokens to create a balance store with 100 tokens
    let test_coin = coin::mint_for_testing<TestCoin>(100, &mut ctx);
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin, &mut ctx);

    // Artificially inflate the totals to exceed actual balance
    // Balance store has 100 tokens, but we set totals to exceed that
    deusd_lp_staking::update_stake_parameters_for_test<TestCoin>(
        &mut staking_management,
        80,
        50,
    );

    // This should abort with error EInvariantBroken: 100 < (80 + 50 = 130)
    deusd_lp_staking::run_invariant_check_for_test<TestCoin>(&staking_management);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
}

// === Multi-User Tests ===

#[test]
fun test_multiple_users_stake_same_token() {
    let mut ts = test_scenario::begin(@elixir);

    let admin_cap = admin_cap::create_for_test(ts.ctx());
    let global_config = config::create_for_test(ts.ctx());
    let mut staking_management = deusd_lp_staking::create_for_test(ts.ctx());

    // Set up stake parameters
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // User 1 stakes 100 tokens
    ts.next_tx(BOB1);
    let test_coin1 = coin::mint_for_testing<TestCoin>(100, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin1, ts.ctx());

    // User 2 stakes 200 tokens
    ts.next_tx(BOB2);
    let test_coin2 = coin::mint_for_testing<TestCoin>(200, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin2, ts.ctx());

    // User 3 stakes 150 tokens
    ts.next_tx(BOB3);
    let test_coin3 = coin::mint_for_testing<TestCoin>(150, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin3, ts.ctx());

    // Verify individual user stakes
    let (staked1, cooling1, _) = deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, BOB1);
    let (staked2, cooling2, _) = deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, BOB2);
    let (staked3, cooling3, _) = deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, BOB3);

    assert_eq(staked1, 100);
    assert_eq(cooling1, 0);
    assert_eq(staked2, 200);
    assert_eq(cooling2, 0);
    assert_eq(staked3, 150);
    assert_eq(cooling3, 0);

    // Verify total stakes
    let (_, _, _, total_staked, total_cooling_down) =
        deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);
    assert_eq(total_staked, 450); // 100 + 200 + 150
    assert_eq(total_cooling_down, 0);

    // Verify contract balance
    assert_eq(deusd_lp_staking::get_balance<TestCoin>(&staking_management), 450);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
    ts.end();
}

#[test]
fun test_multiple_users_unstake_different_amounts() {
    let mut ts = test_scenario::begin(@elixir);

    let admin_cap = admin_cap::create_for_test(ts.ctx());
    let global_config = config::create_for_test(ts.ctx());
    let clock_obj = clock::create_for_testing(ts.ctx());
    let mut staking_management = deusd_lp_staking::create_for_test(ts.ctx());

    // Set up stake parameters
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // Multiple users stake tokens
    ts.next_tx(BOB1);
    let test_coin1 = coin::mint_for_testing<TestCoin>(100, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin1, ts.ctx());

    ts.next_tx(BOB2);
    let test_coin2 = coin::mint_for_testing<TestCoin>(200, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin2, ts.ctx());

    ts.next_tx(BOB3);
    let test_coin3 = coin::mint_for_testing<TestCoin>(300, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin3, ts.ctx());

    // Users unstake different amounts
    ts.next_tx(BOB1);
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 50, &clock_obj, ts.ctx());

    ts.next_tx(BOB2);
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 100, &clock_obj, ts.ctx());

    ts.next_tx(BOB3);
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 200, &clock_obj, ts.ctx());

    // Verify individual user states
    let (staked1, cooling1, _) = deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, BOB1);
    let (staked2, cooling2, _) = deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, BOB2);
    let (staked3, cooling3, _) = deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, BOB3);

    assert_eq(staked1, 50);  // 100 - 50
    assert_eq(cooling1, 50);
    assert_eq(staked2, 100); // 200 - 100
    assert_eq(cooling2, 100);
    assert_eq(staked3, 100); // 300 - 200
    assert_eq(cooling3, 200);

    // Verify totals
    let (_, _, _, total_staked, total_cooling_down) =
        deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);
    assert_eq(total_staked, 250);    // 50 + 100 + 100
    assert_eq(total_cooling_down, 350); // 50 + 100 + 200

    // Contract balance should remain unchanged
    assert_eq(deusd_lp_staking::get_balance<TestCoin>(&staking_management), 600);

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
    ts.end();
}

#[test]
fun test_multiple_users_withdraw_after_cooldown() {
    let mut ts = test_scenario::begin(@elixir);

    let admin_cap = admin_cap::create_for_test(ts.ctx());
    let global_config = config::create_for_test(ts.ctx());
    let mut clock_obj = clock::create_for_testing(ts.ctx());
    let mut staking_management = deusd_lp_staking::create_for_test(ts.ctx());

    // Set up stake parameters
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 1000, 86400,
    );

    // Multiple users stake and unstake tokens
    ts.next_tx(BOB1);
    let test_coin1 = coin::mint_for_testing<TestCoin>(100, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin1, ts.ctx());
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 60, &clock_obj, ts.ctx());

    ts.next_tx(BOB2);
    let test_coin2 = coin::mint_for_testing<TestCoin>(200, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin2, ts.ctx());
    deusd_lp_staking::unstake<TestCoin>(&mut staking_management, &global_config, 80, &clock_obj, ts.ctx());

    // Wait for cooldown period to pass
    clock::increment_for_testing(&mut clock_obj, 86401 * 1000);

    // Users withdraw different amounts
    ts.next_tx(BOB1);
    deusd_lp_staking::withdraw<TestCoin>(&mut staking_management, &global_config, 40, &clock_obj, ts.ctx());

    ts.next_tx(BOB2);
    deusd_lp_staking::withdraw<TestCoin>(&mut staking_management, &global_config, 60, &clock_obj, ts.ctx());

    // Verify final states
    let (staked1, cooling1, _) = deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, BOB1);
    let (staked2, cooling2, _) = deusd_lp_staking::get_stake_data<TestCoin>(&staking_management, BOB2);

    assert_eq(staked1, 40);  // 100 - 60 (unstaked)
    assert_eq(cooling1, 20); // 60 - 40 (withdrawn)
    assert_eq(staked2, 120); // 200 - 80 (unstaked)
    assert_eq(cooling2, 20); // 80 - 60 (withdrawn)

    // Verify totals
    let (_, _, _, total_staked, total_cooling_down) =
        deusd_lp_staking::get_stake_parameters<TestCoin>(&staking_management);
    assert_eq(total_staked, 160);    // 40 + 120
    assert_eq(total_cooling_down, 40); // 20 + 20

    // Contract balance should be reduced by withdrawn amounts
    assert_eq(deusd_lp_staking::get_balance<TestCoin>(&staking_management), 200); // 300 - 100 (withdrawn)

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    clock::destroy_for_testing(clock_obj);
    deusd_lp_staking::destroy_for_test(staking_management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_lp_staking::EStakeLimitExceeded)]
fun test_multiple_users_exceed_stake_limit() {
    let mut ts = test_scenario::begin(@elixir);

    let admin_cap = admin_cap::create_for_test(ts.ctx());
    let global_config = config::create_for_test(ts.ctx());
    let mut staking_management = deusd_lp_staking::create_for_test(ts.ctx());

    // Set up stake parameters with a low limit
    deusd_lp_staking::set_epoch(&admin_cap, &mut staking_management, &global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        &admin_cap,
        &mut staking_management,
        &global_config,
        1, 250, 86400, // Low stake limit
    );

    // User 1 stakes most of the capacity
    ts.next_tx(BOB1);
    let test_coin1 = coin::mint_for_testing<TestCoin>(200, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin1, ts.ctx());

    // User 2 tries to stake more than remaining capacity - should fail
    ts.next_tx(BOB2);
    // This would exceed limit (200 + 100 > 250)
    let test_coin2 = coin::mint_for_testing<TestCoin>(100, ts.ctx());
    deusd_lp_staking::stake(&mut staking_management, &global_config, test_coin2, ts.ctx());

    sui::test_utils::destroy(admin_cap);
    config::destroy_for_test(global_config);
    deusd_lp_staking::destroy_for_test(staking_management);
    ts.end();
}

// === Helper Functions ===

fun setup_staking_with_stake(
    admin_cap: &AdminCap,
    global_config: &GlobalConfig,
    ctx: &mut TxContext,
): DeUSDLPStakingManagement {
    let mut staking_management = deusd_lp_staking::create_for_test(ctx);

    // Set up stake parameters
    deusd_lp_staking::set_epoch(admin_cap, &mut staking_management, global_config, 1);
    deusd_lp_staking::update_stake_parameters<TestCoin>(
        admin_cap,
        &mut staking_management,
        global_config,
        1, 1000, 86400,
    );

    // Stake tokens
    let test_coin = coin::mint_for_testing<TestCoin>(100, ctx);
    deusd_lp_staking::stake(&mut staking_management, global_config, test_coin, ctx);

    staking_management
}
