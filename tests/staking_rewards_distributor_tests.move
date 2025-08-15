#[test_only]
module elixir::staking_rewards_distributor_tests;

use elixir::test_utils;
use elixir::staking_rewards_distributor::{Self, StakingRewardsDistributor};
use elixir::deusd::{Self, DEUSD, DeUSDConfig};
use elixir::admin_cap::{Self, AdminCap};
use elixir::config::{Self, GlobalConfig};
use elixir::sdeusd::SdeUSDManagement;
use elixir::roles;
use sui::test_scenario;
use sui::coin;
use sui::clock;

// === Test Constants ===

const ADMIN: address = @0xad;
const OPERATOR: address = @0x01234;
const USER: address = @0xa11ce;
const NEW_OPERATOR: address = @0xb0b;

// === Initialization Tests ===

#[test]
fun test_initialization() {
    let (ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management) = setup_test();
    
    // Test initial state
    assert!(staking_rewards_distributor::get_operator(&distributor) == @0x0);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 0);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

// === Operator Management Tests ===

#[test]
fun test_set_operator_success() {
    let (mut ts, admin_cap, deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    // Set new operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    
    // Verify operator was set
    assert!(staking_rewards_distributor::get_operator(&distributor) == OPERATOR);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_set_operator_to_zero_address() {
    let (mut ts, admin_cap, deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    // First set a real operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == OPERATOR);
    
    // Then set to zero address (should be allowed for emergency removal)
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, @0x0, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == @0x0);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_replace_operator() {
    let (mut ts, admin_cap, deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    // Set initial operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == OPERATOR);
    
    // Replace with new operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, NEW_OPERATOR, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == NEW_OPERATOR);
    
    // Test multiple operator changes for state consistency
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, ADMIN, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == ADMIN);
    
    // Set back to zero address
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, @0x0, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == @0x0);
    
    // Set back to original operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == OPERATOR);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

// === Deposit Tests ===

#[test]
fun test_deposit_deusd_success() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    ts.next_tx(USER);
    
    // Mint some deUSD
    let deusd_coin = mint_deusd(&mut deusd_config, USER, 1000_000_000, &mut ts);
    
    // Deposit to distributor
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin, ts.ctx());
    
    // Verify balance was updated
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000_000_000);
    
    // Test state consistency - balance should persist across transactions
    ts.next_tx(ADMIN);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000_000_000);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_deposit_multiple_times() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    ts.next_tx(USER);
    
    // First deposit
    let deusd_coin1 = mint_deusd(&mut deusd_config, USER, 500_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin1, ts.ctx());
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 500_000_000);
    
    // Second deposit
    let deusd_coin2 = mint_deusd(&mut deusd_config, USER, 500_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin2, ts.ctx());
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000_000_000);
    
    // Test deposits from different users
    ts.next_tx(ADMIN);
    let admin_coin = mint_deusd(&mut deusd_config, ADMIN, 100_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, admin_coin, ts.ctx());
    
    // Verify total balance includes all deposits
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000_000_000 + 100_000_000);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_deposit_zero_amount() {
    let (mut ts, admin_cap, deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    ts.next_tx(USER);
    
    // Deposit zero amount (should work but have no effect)
    let zero_coin = coin::zero<DEUSD>(ts.ctx());
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, zero_coin, ts.ctx());
    
    // Balance should remain zero
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 0);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_deposit_minimum_amount() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    ts.next_tx(USER);
    let min_coin = mint_deusd(&mut deusd_config, USER, 1, &mut ts); // 1 unit (smallest possible)
    
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, min_coin, ts.ctx());
    
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

// === Withdraw Tests ===

#[test]
fun test_withdraw_deusd_success() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    // First deposit some funds
    ts.next_tx(USER);
    let deusd_coin = mint_deusd(&mut deusd_config, USER, 1000_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin, ts.ctx());
    
    // Admin withdraws half
    ts.next_tx(ADMIN);
    staking_rewards_distributor::withdraw_deusd(&admin_cap, &mut distributor, &global_config, 500_000_000, USER, ts.ctx());
    
    // Check remaining balance
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 500_000_000);
    
    // Check that USER received the withdrawn amount
    ts.next_tx(USER);
    let received_coin = ts.take_from_address<coin::Coin<DEUSD>>(USER);
    assert!(received_coin.value() == 500_000_000);
    coin::burn_for_testing(received_coin);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
#[expected_failure(abort_code = staking_rewards_distributor::EInvalidAmount)]
fun test_withdraw_zero_amount() {
    let (mut ts, admin_cap, deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    staking_rewards_distributor::withdraw_deusd(&admin_cap, &mut distributor, &global_config, 0, USER, ts.ctx());
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
#[expected_failure]
fun test_withdraw_insufficient_balance() {
    let (mut ts, admin_cap, deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    // Try to withdraw more than available (distributor has 0 balance)
    staking_rewards_distributor::withdraw_deusd(&admin_cap, &mut distributor, &global_config, 100_000_000, USER, ts.ctx());
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_withdraw_minimum_amount() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    // Deposit some funds first
    ts.next_tx(USER);
    let deusd_coin = mint_deusd(&mut deusd_config, USER, 100_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin, ts.ctx());
    
    // Withdraw minimum amount
    ts.next_tx(ADMIN);
    staking_rewards_distributor::withdraw_deusd(&admin_cap, &mut distributor, &global_config, 1, USER, ts.ctx());
    
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 100_000_000 - 1);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

// === Transfer Rewards Tests ===

#[test]
fun test_transfer_in_rewards_success() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, mut sdeusd_management) = setup_test();
    
    // Set operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    
    // Deposit funds
    ts.next_tx(USER);
    let deusd_coin = mint_deusd(&mut deusd_config, USER, 1000_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin, ts.ctx());
    
    // Operator transfers rewards
    ts.next_tx(OPERATOR);
    let mut clock = clock::create_for_testing(ts.ctx());
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        500_000_000,
        &clock,
        ts.ctx()
    );
    
    // Check remaining balance in distributor
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 500_000_000);
    
    // Test transferring exact remaining balance
    clock::increment_for_testing(&mut clock, 8 * 3600 * 1000); // Advance vesting period
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        500_000_000,
        &clock,
        ts.ctx()
    );
    
    // Balance should now be exactly zero
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 0);
    
    clock::destroy_for_testing(clock);
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_transfer_in_rewards_multiple_times() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, mut sdeusd_management) = setup_test();
    
    // Set operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    
    // Deposit funds
    ts.next_tx(USER);
    let deusd_coin = mint_deusd(&mut deusd_config, USER, 1000_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin, ts.ctx());
    
    // First transfer
    ts.next_tx(OPERATOR);
    let mut clock = clock::create_for_testing(ts.ctx());
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        100_000_000,
        &clock,
        ts.ctx()
    );
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000_000_000 - 100_000_000);
    
    // Advance clock by vesting period (8 hours in milliseconds) before second transfer
    let vesting_period = 8 * 3600 * 1000; // 8 hours
    clock::increment_for_testing(&mut clock, vesting_period);
    
    // Second transfer
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        50_000_000,
        &clock,
        ts.ctx()
    );
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000_000_000 - 100_000_000 - 50_000_000);
    
    clock::destroy_for_testing(clock);
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
#[expected_failure(abort_code = staking_rewards_distributor::EOnlyOperator)]
fun test_transfer_in_rewards_unauthorized() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, mut sdeusd_management) = setup_test();
    
    // Set operator (not USER)
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    
    // Deposit funds
    ts.next_tx(USER);
    let deusd_coin = mint_deusd(&mut deusd_config, USER, 1000_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin, ts.ctx());
    
    // USER (not operator) tries to transfer rewards
    let clock = clock::create_for_testing(ts.ctx());
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        500_000_000,
        &clock,
        ts.ctx()
    );
    
    clock::destroy_for_testing(clock);
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
#[expected_failure(abort_code = staking_rewards_distributor::EInsufficientFunds)]
fun test_transfer_in_rewards_insufficient_balance() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, mut sdeusd_management) = setup_test();
    
    // Set operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    
    // Deposit smaller amount
    ts.next_tx(USER);
    let deusd_coin = mint_deusd(&mut deusd_config, USER, 100_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin, ts.ctx());
    
    // Try to transfer more than available
    ts.next_tx(OPERATOR);
    let clock = clock::create_for_testing(ts.ctx());
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        500_000_000,
        &clock,
        ts.ctx()
    );
    
    clock::destroy_for_testing(clock);
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
#[expected_failure(abort_code = staking_rewards_distributor::EOnlyOperator)]
fun test_transfer_in_rewards_if_not_operator() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, mut sdeusd_management) = setup_test();
    
    // Don't set operator (remains @0x0)
    
    // Deposit funds
    ts.next_tx(USER);
    let deusd_coin = mint_deusd(&mut deusd_config, USER, 1000_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin, ts.ctx());
    
    // Try to transfer rewards without being operator
    let clock = clock::create_for_testing(ts.ctx());
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        500_000_000,
        &clock,
        ts.ctx()
    );
    
    clock::destroy_for_testing(clock);
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_transfer_in_rewards_minimum_amount() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, mut sdeusd_management) = setup_test();
    
    // Set operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    
    // Deposit funds
    ts.next_tx(USER);
    let deusd_coin = mint_deusd(&mut deusd_config, USER, 100_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin, ts.ctx());
    
    // Transfer minimum amount
    ts.next_tx(OPERATOR);
    let clock = clock::create_for_testing(ts.ctx());
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        1, // Minimum amount
        &clock,
        ts.ctx()
    );
    
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 100_000_000 - 1);
    
    clock::destroy_for_testing(clock);
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

// === Integration Tests ===

#[test]
fun test_full_workflow() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, mut sdeusd_management) = setup_test();
    
    // 1. Admin sets operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == OPERATOR);
    
    // 2. Users deposit deUSD
    ts.next_tx(USER);
    let deusd_coin1 = mint_deusd(&mut deusd_config, USER, 500_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin1, ts.ctx());
    
    ts.next_tx(ADMIN);
    let deusd_coin2 = mint_deusd(&mut deusd_config, ADMIN, 500_000_000, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, deusd_coin2, ts.ctx());
    
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000_000_000);
    
    // 3. Operator transfers rewards multiple times
    ts.next_tx(OPERATOR);
    let mut clock = clock::create_for_testing(ts.ctx());
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        100_000_000,
        &clock,
        ts.ctx()
    );
    
    // Advance clock by vesting period before second transfer
    let vesting_period = 8 * 3600 * 1000; // 8 hours
    clock::increment_for_testing(&mut clock, vesting_period);
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        50_000_000,
        &clock,
        ts.ctx()
    );
    
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000_000_000 - 100_000_000 - 50_000_000);
    
    // 4. Admin withdraws some funds
    ts.next_tx(ADMIN);
    staking_rewards_distributor::withdraw_deusd(&admin_cap, &mut distributor, &global_config, 100_000_000, ADMIN, ts.ctx());
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000_000_000 - 100_000_000 - 50_000_000 - 100_000_000);
    
    // 5. Admin changes operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, NEW_OPERATOR, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == NEW_OPERATOR);
    
    // 6. New operator can transfer rewards
    ts.next_tx(NEW_OPERATOR);
    
    // Advance clock by vesting period before new operator transfer
    clock::increment_for_testing(&mut clock, vesting_period);
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        50_000_000,
        &clock,
        ts.ctx()
    );
    
    // 7. Old operator can no longer transfer rewards (would fail)
    // ts.next_tx(OPERATOR);
    // This would fail: staking_rewards_distributor::transfer_in_rewards(...)
    
    clock::destroy_for_testing(clock);
    
    // Clean up withdrawn coins
    ts.next_tx(ADMIN);
    let withdrawn_coin = ts.take_from_address<coin::Coin<DEUSD>>(ADMIN);
    coin::burn_for_testing(withdrawn_coin);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

// === Edge Cases ===

#[test]
fun test_operator_can_be_set_to_admin() {
    let (mut ts, admin_cap, deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    // Admin sets themselves as operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, ADMIN, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == ADMIN);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_zero_balance_operations() {
    let (mut ts, admin_cap, deusd_config, mut distributor, global_config, sdeusd_management) = setup_test();
    
    // Set operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    
    // Try to transfer with zero balance - should fail
    ts.next_tx(OPERATOR);
    // This would fail: staking_rewards_distributor::transfer_in_rewards(&mut distributor, ...)
    
    // Check balance is still zero
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 0);
    
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

#[test]
fun test_large_amounts() {
    let (mut ts, admin_cap, mut deusd_config, mut distributor, global_config, mut sdeusd_management) = setup_test();
    
    // Set operator
    staking_rewards_distributor::set_operator(&admin_cap, &mut distributor, &global_config, OPERATOR, ts.ctx());
    
    // Use maximum reasonable amounts
    let large_amount = 1_000_000_000_000_000; // 1 billion tokens
    
    ts.next_tx(USER);
    let large_coin = mint_deusd(&mut deusd_config, USER, large_amount, &mut ts);
    staking_rewards_distributor::deposit_deusd(&mut distributor, &global_config, large_coin, ts.ctx());
    
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == large_amount);
    
    // Transfer half
    ts.next_tx(OPERATOR);
    let clock = clock::create_for_testing(ts.ctx());
    
    staking_rewards_distributor::transfer_in_rewards(
        &mut distributor,
        &mut sdeusd_management,
        &global_config,
        large_amount / 2,
        &clock,
        ts.ctx()
    );
    
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == large_amount / 2);
    
    clock::destroy_for_testing(clock);
    clean_test(ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management);
}

// === Test Setup Helper Functions ===

fun mint_deusd(deusd_config: &mut DeUSDConfig, to: address, amount: u64, ts: &mut test_scenario::Scenario): coin::Coin<DEUSD> {
    deusd::mint_for_test(deusd_config, to, amount, ts.ctx())
}

fun setup_test(): (test_scenario::Scenario, AdminCap, DeUSDConfig, StakingRewardsDistributor, GlobalConfig, SdeUSDManagement) {
    let mut ts = test_scenario::begin(ADMIN);
    let (mut global_config, admin_cap) = test_utils::setup_global_config(&mut ts, ADMIN);
    let deusd_config = test_utils::setup_deusd(&mut ts, ADMIN);
    let distributor = test_utils::setup_staking_rewards_distributor(&mut ts, ADMIN);
    let sdeusd_management = test_utils::setup_sdeusd(&mut ts, ADMIN);

    // Grant rewarder role to OPERATOR and NEW_OPERATOR so they can call transfer_in_rewards
    config::add_role(&admin_cap, &mut global_config, OPERATOR, roles::role_rewarder());
    config::add_role(&admin_cap, &mut global_config, NEW_OPERATOR, roles::role_rewarder());

    (ts, admin_cap, deusd_config, distributor, global_config, sdeusd_management)
}

fun clean_test(ts: test_scenario::Scenario, admin_cap: AdminCap, deusd_config: DeUSDConfig, distributor: StakingRewardsDistributor, global_config: GlobalConfig, sdeusd_management: SdeUSDManagement) {
    test_scenario::return_shared(deusd_config);
    test_scenario::return_shared(distributor);
    test_scenario::return_shared(global_config);
    test_scenario::return_shared(sdeusd_management);
    admin_cap::destroy_for_test(admin_cap);
    test_scenario::end(ts);
}