#[test_only]
module elixir::staking_rewards_distributor_tests;

use elixir::staking_rewards_distributor::{Self, StakingRewardsDistributor};
use elixir::deusd;
use sui::test_scenario;
use sui::coin;

// Test constants
const ADMIN: address = @0xad;
const OPERATOR: address = @0x123;
const USER1: address = @0xa11ce;
const STAKING_VAULT: address = @0x456;

// Test token types
public struct TestToken has drop {}

#[test]
fun test_initialization() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Test basic initialization
    assert!(staking_rewards_distributor::get_admin(&distributor) == ADMIN, 0);
    assert!(staking_rewards_distributor::get_operator(&distributor) == @0x0, 1);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 0, 2);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_create_distributor() {
    let mut ts = test_scenario::begin(ADMIN);
    
    let assets = vector[@0x123, @0x456];
    
    staking_rewards_distributor::create_distributor(
        STAKING_VAULT,
        assets,
        ADMIN,
        OPERATOR,
        ts.ctx()
    );
    
    ts.next_tx(ADMIN);
    let distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Verify initialization
    assert!(staking_rewards_distributor::get_admin(&distributor) == ADMIN, 0);
    assert!(staking_rewards_distributor::get_operator(&distributor) == OPERATOR, 1);
    assert!(staking_rewards_distributor::get_staking_vault(&distributor) == STAKING_VAULT, 2);
    assert!(vector::length(staking_rewards_distributor::get_approved_assets(&distributor)) == 2, 3);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_set_operator() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Set operator
    staking_rewards_distributor::set_operator(&mut distributor, OPERATOR, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == OPERATOR, 0);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_set_staking_vault() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Set staking vault
    staking_rewards_distributor::set_staking_vault(&mut distributor, STAKING_VAULT, ts.ctx());
    assert!(staking_rewards_distributor::get_staking_vault(&distributor) == STAKING_VAULT, 0);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_add_deusd_balance_and_transfer_rewards() {
    let mut ts = test_scenario::begin(ADMIN);
    
    // Initialize deUSD first
    deusd::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<deusd::Management>();
    
    // Mint some deUSD
    let deusd_coin = deusd::mint(&mut management, USER1, 1000, ts.ctx());
    
    // Initialize distributor
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Set operator and staking vault
    staking_rewards_distributor::set_operator(&mut distributor, OPERATOR, ts.ctx());
    staking_rewards_distributor::set_staking_vault(&mut distributor, STAKING_VAULT, ts.ctx());
    
    // Add deUSD balance to distributor
    staking_rewards_distributor::add_deusd_balance(&mut distributor, deusd_coin);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000, 0);
    
    ts.next_tx(OPERATOR);
    
    // Transfer rewards as operator
    let reward_coin = staking_rewards_distributor::transfer_in_rewards(
        &mut distributor, 500, ts.ctx()
    );
    
    assert!(coin::value(&reward_coin) == 500, 1);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 500, 2);
    
    coin::burn_for_testing(reward_coin);
    test_scenario::return_shared(distributor);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_rescue_deusd_tokens() {
    let mut ts = test_scenario::begin(ADMIN);
    
    // Initialize deUSD first
    deusd::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<deusd::Management>();
    
    // Mint some deUSD
    let deusd_coin = deusd::mint(&mut management, USER1, 1000, ts.ctx());
    
    // Initialize distributor
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Add deUSD balance to distributor
    staking_rewards_distributor::add_deusd_balance(&mut distributor, deusd_coin);
    
    // Rescue tokens as admin
    let rescued_coin = staking_rewards_distributor::rescue_deusd_tokens(
        &mut distributor, 300, USER1, ts.ctx()
    );
    
    assert!(coin::value(&rescued_coin) == 300, 0);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 700, 1);
    
    coin::burn_for_testing(rescued_coin);
    test_scenario::return_shared(distributor);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_token_balance_operations() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Create token balance using the public function
    let mut token_balance = staking_rewards_distributor::create_token_balance<TestToken>(ts.ctx());
    
    // Add token balance
    let test_coin = coin::mint_for_testing<TestToken>(500, ts.ctx());
    staking_rewards_distributor::add_token_balance(&mut token_balance, test_coin);
    
    assert!(staking_rewards_distributor::get_token_balance(&token_balance) == 500, 0);
    
    // Rescue tokens
    let rescued_coin = staking_rewards_distributor::rescue_tokens(
        &distributor, &mut token_balance, 200, USER1, ts.ctx()
    );
    
    assert!(coin::value(&rescued_coin) == 200, 1);
    assert!(staking_rewards_distributor::get_token_balance(&token_balance) == 300, 2);
    
    coin::burn_for_testing(rescued_coin);
    transfer::public_transfer(token_balance, ADMIN);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_approve_and_revoke_assets() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Approve assets
    let assets = vector[@0x123, @0x456, @0x789];
    staking_rewards_distributor::approve_assets(&mut distributor, assets, ts.ctx());
    
    assert!(vector::length(staking_rewards_distributor::get_approved_assets(&distributor)) == 3, 0);
    
    // Revoke approvals from self
    let revoke_assets = vector[@0x123, @0x456];
    let distributor_id = staking_rewards_distributor::get_distributor_id(&distributor);
    staking_rewards_distributor::revoke_approvals(
        &mut distributor, 
        revoke_assets, 
        distributor_id,
        ts.ctx()
    );
    
    assert!(vector::length(staking_rewards_distributor::get_approved_assets(&distributor)) == 1, 1);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_transfer_admin() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Transfer admin
    staking_rewards_distributor::transfer_admin(&mut distributor, USER1, ts.ctx());
    assert!(staking_rewards_distributor::get_admin(&distributor) == USER1, 0);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

// ==================== FAILURE CASE TESTS ====================

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidZeroAddress)]
fun test_create_distributor_invalid_staking_vault() {
    let mut ts = test_scenario::begin(ADMIN);
    
    let assets = vector[@0x123];
    
    staking_rewards_distributor::create_distributor(
        @0x0, // Invalid staking vault
        assets,
        ADMIN,
        OPERATOR,
        ts.ctx()
    );
    
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENoAssetsProvided)]
fun test_create_distributor_no_assets() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::create_distributor(
        STAKING_VAULT,
        vector::empty<address>(), // No assets
        ADMIN,
        OPERATOR,
        ts.ctx()
    );
    
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidZeroAddress)]
fun test_create_distributor_invalid_admin() {
    let mut ts = test_scenario::begin(ADMIN);
    
    let assets = vector[@0x123];
    
    staking_rewards_distributor::create_distributor(
        STAKING_VAULT,
        assets,
        @0x0, // Invalid admin
        OPERATOR,
        ts.ctx()
    );
    
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidZeroAddress)]
fun test_create_distributor_invalid_operator() {
    let mut ts = test_scenario::begin(ADMIN);
    
    let assets = vector[@0x123];
    
    staking_rewards_distributor::create_distributor(
        STAKING_VAULT,
        assets,
        ADMIN,
        @0x0, // Invalid operator
        ts.ctx()
    );
    
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENotOwner)]
fun test_set_operator_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(USER1); // Switch to unauthorized user
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Should fail - USER1 is not admin
    staking_rewards_distributor::set_operator(&mut distributor, OPERATOR, ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EOnlyOperator)]
fun test_transfer_rewards_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    ts.next_tx(USER1); // Switch to unauthorized user
    
    // Should fail - USER1 is not operator
    let _reward_coin = staking_rewards_distributor::transfer_in_rewards(
        &mut distributor, 500, ts.ctx()
    );
    
    coin::burn_for_testing(_reward_coin);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInsufficientFunds)]
fun test_transfer_rewards_insufficient_funds() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Set operator
    staking_rewards_distributor::set_operator(&mut distributor, OPERATOR, ts.ctx());
    
    ts.next_tx(OPERATOR);
    
    // Should fail - no deUSD balance in distributor
    let _reward_coin = staking_rewards_distributor::transfer_in_rewards(
        &mut distributor, 500, ts.ctx()
    );
    
    coin::burn_for_testing(_reward_coin);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENotOwner)]
fun test_rescue_tokens_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    ts.next_tx(USER1); // Switch to unauthorized user
    
    // Should fail - USER1 is not admin
    let _rescued_coin = staking_rewards_distributor::rescue_deusd_tokens(
        &mut distributor, 100, USER1, ts.ctx()
    );
    
    coin::burn_for_testing(_rescued_coin);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidZeroAddress)]
fun test_rescue_tokens_invalid_recipient() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Should fail - invalid recipient address
    let _rescued_coin = staking_rewards_distributor::rescue_deusd_tokens(
        &mut distributor, 100, @0x0, ts.ctx()
    );
    
    coin::burn_for_testing(_rescued_coin);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidAmount)]
fun test_rescue_tokens_zero_amount() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Should fail - zero amount
    let _rescued_coin = staking_rewards_distributor::rescue_deusd_tokens(
        &mut distributor, 0, USER1, ts.ctx()
    );
    
    coin::burn_for_testing(_rescued_coin);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENotOwner)]
fun test_transfer_admin_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(USER1); // Switch to unauthorized user
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Should fail - USER1 is not admin
    staking_rewards_distributor::transfer_admin(&mut distributor, USER1, ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

// ==================== ADDITIONAL COMPREHENSIVE TESTS ====================

#[test]
fun test_set_operator_to_zero_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // First set a valid operator
    staking_rewards_distributor::set_operator(&mut distributor, OPERATOR, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == OPERATOR, 0);
    
    // Set operator to zero address (allowed for emergency situations)
    staking_rewards_distributor::set_operator(&mut distributor, @0x0, ts.ctx());
    assert!(staking_rewards_distributor::get_operator(&distributor) == @0x0, 1);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_multiple_deusd_balance_additions() {
    let mut ts = test_scenario::begin(ADMIN);
    
    // Initialize deUSD first
    deusd::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<deusd::Management>();
    
    // Initialize distributor
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Add multiple deUSD balances
    let deusd_coin1 = deusd::mint(&mut management, USER1, 1000, ts.ctx());
    let deusd_coin2 = deusd::mint(&mut management, USER1, 500, ts.ctx());
    let deusd_coin3 = deusd::mint(&mut management, USER1, 250, ts.ctx());
    
    staking_rewards_distributor::add_deusd_balance(&mut distributor, deusd_coin1);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000, 0);
    
    staking_rewards_distributor::add_deusd_balance(&mut distributor, deusd_coin2);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1500, 1);
    
    staking_rewards_distributor::add_deusd_balance(&mut distributor, deusd_coin3);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1750, 2);
    
    test_scenario::return_shared(distributor);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_partial_reward_transfers() {
    let mut ts = test_scenario::begin(ADMIN);
    
    // Initialize deUSD first
    deusd::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<deusd::Management>();
    
    // Mint some deUSD
    let deusd_coin = deusd::mint(&mut management, USER1, 1000, ts.ctx());
    
    // Initialize distributor
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Set operator and add balance
    staking_rewards_distributor::set_operator(&mut distributor, OPERATOR, ts.ctx());
    staking_rewards_distributor::add_deusd_balance(&mut distributor, deusd_coin);
    
    ts.next_tx(OPERATOR);
    
    // Multiple partial transfers
    let reward1 = staking_rewards_distributor::transfer_in_rewards(&mut distributor, 300, ts.ctx());
    assert!(coin::value(&reward1) == 300, 0);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 700, 1);
    
    let reward2 = staking_rewards_distributor::transfer_in_rewards(&mut distributor, 200, ts.ctx());
    assert!(coin::value(&reward2) == 200, 2);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 500, 3);
    
    let reward3 = staking_rewards_distributor::transfer_in_rewards(&mut distributor, 500, ts.ctx());
    assert!(coin::value(&reward3) == 500, 4);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 0, 5);
    
    coin::burn_for_testing(reward1);
    coin::burn_for_testing(reward2);
    coin::burn_for_testing(reward3);
    test_scenario::return_shared(distributor);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_approve_duplicate_assets() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Approve initial assets
    let assets1 = vector[@0x123, @0x456];
    staking_rewards_distributor::approve_assets(&mut distributor, assets1, ts.ctx());
    assert!(vector::length(staking_rewards_distributor::get_approved_assets(&distributor)) == 2, 0);
    
    // Approve overlapping assets (should not duplicate)
    let assets2 = vector[@0x456, @0x789]; // @0x456 is duplicate
    staking_rewards_distributor::approve_assets(&mut distributor, assets2, ts.ctx());
    assert!(vector::length(staking_rewards_distributor::get_approved_assets(&distributor)) == 3, 1);
    
    // Verify specific assets are present
    let approved = staking_rewards_distributor::get_approved_assets(&distributor);
    assert!(vector::contains(approved, &@0x123), 2);
    assert!(vector::contains(approved, &@0x456), 3);
    assert!(vector::contains(approved, &@0x789), 4);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_revoke_nonexistent_assets() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Approve some assets
    let assets = vector[@0x123, @0x456];
    staking_rewards_distributor::approve_assets(&mut distributor, assets, ts.ctx());
    assert!(vector::length(staking_rewards_distributor::get_approved_assets(&distributor)) == 2, 0);
    
    // Try to revoke assets that don't exist (should not fail, just no-op)
    let revoke_assets = vector[@0x999, @0x888]; // Non-existent assets
    let distributor_id = staking_rewards_distributor::get_distributor_id(&distributor);
    staking_rewards_distributor::revoke_approvals(&mut distributor, revoke_assets, distributor_id, ts.ctx());
    
    // Should still have original 2 assets
    assert!(vector::length(staking_rewards_distributor::get_approved_assets(&distributor)) == 2, 1);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_revoke_from_external_target() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Approve some assets
    let assets = vector[@0x123, @0x456, @0x789];
    staking_rewards_distributor::approve_assets(&mut distributor, assets, ts.ctx());
    assert!(vector::length(staking_rewards_distributor::get_approved_assets(&distributor)) == 3, 0);
    
    // Revoke from external target (should not affect our approved list)
    let revoke_assets = vector[@0x123, @0x456];
    staking_rewards_distributor::revoke_approvals(&mut distributor, revoke_assets, @0x999, ts.ctx());
    
    // Should still have all 3 assets since we revoked from external target
    assert!(vector::length(staking_rewards_distributor::get_approved_assets(&distributor)) == 3, 1);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_multiple_token_balance_operations() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Create multiple token balance objects
    let mut token_balance1 = staking_rewards_distributor::create_token_balance<TestToken>(ts.ctx());
    let mut token_balance2 = staking_rewards_distributor::create_token_balance<TestToken>(ts.ctx());
    
    // Add tokens to both balances
    let test_coin1 = coin::mint_for_testing<TestToken>(1000, ts.ctx());
    let test_coin2 = coin::mint_for_testing<TestToken>(500, ts.ctx());
    let test_coin3 = coin::mint_for_testing<TestToken>(300, ts.ctx());
    
    staking_rewards_distributor::add_token_balance(&mut token_balance1, test_coin1);
    staking_rewards_distributor::add_token_balance(&mut token_balance1, test_coin2);
    staking_rewards_distributor::add_token_balance(&mut token_balance2, test_coin3);
    
    assert!(staking_rewards_distributor::get_token_balance(&token_balance1) == 1500, 0);
    assert!(staking_rewards_distributor::get_token_balance(&token_balance2) == 300, 1);
    
    // Rescue from both balances
    let rescued1 = staking_rewards_distributor::rescue_tokens(&distributor, &mut token_balance1, 600, USER1, ts.ctx());
    let rescued2 = staking_rewards_distributor::rescue_tokens(&distributor, &mut token_balance2, 100, USER1, ts.ctx());
    
    assert!(coin::value(&rescued1) == 600, 2);
    assert!(coin::value(&rescued2) == 100, 3);
    assert!(staking_rewards_distributor::get_token_balance(&token_balance1) == 900, 4);
    assert!(staking_rewards_distributor::get_token_balance(&token_balance2) == 200, 5);
    
    coin::burn_for_testing(rescued1);
    coin::burn_for_testing(rescued2);
    transfer::public_transfer(token_balance1, ADMIN);
    transfer::public_transfer(token_balance2, ADMIN);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_admin_transfer_chain() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Transfer admin from ADMIN to USER1
    staking_rewards_distributor::transfer_admin(&mut distributor, USER1, ts.ctx());
    assert!(staking_rewards_distributor::get_admin(&distributor) == USER1, 0);
    
    ts.next_tx(USER1);
    
    // Transfer admin from USER1 to OPERATOR
    staking_rewards_distributor::transfer_admin(&mut distributor, OPERATOR, ts.ctx());
    assert!(staking_rewards_distributor::get_admin(&distributor) == OPERATOR, 1);
    
    ts.next_tx(OPERATOR);
    
    // OPERATOR should now be able to perform admin actions
    staking_rewards_distributor::set_staking_vault(&mut distributor, STAKING_VAULT, ts.ctx());
    assert!(staking_rewards_distributor::get_staking_vault(&distributor) == STAKING_VAULT, 2);
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_edge_case_rescue_all_deusd_balance() {
    let mut ts = test_scenario::begin(ADMIN);
    
    // Initialize deUSD first
    deusd::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<deusd::Management>();
    
    // Mint some deUSD
    let deusd_coin = deusd::mint(&mut management, USER1, 1000, ts.ctx());
    
    // Initialize distributor
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Add deUSD balance to distributor
    staking_rewards_distributor::add_deusd_balance(&mut distributor, deusd_coin);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 1000, 0);
    
    // Rescue all balance
    let rescued_coin = staking_rewards_distributor::rescue_deusd_tokens(
        &mut distributor, 1000, USER1, ts.ctx()
    );
    
    assert!(coin::value(&rescued_coin) == 1000, 1);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 0, 2);
    
    coin::burn_for_testing(rescued_coin);
    test_scenario::return_shared(distributor);
    test_scenario::return_shared(management);
    ts.end();
}

// ==================== ADDITIONAL FAILURE CASE TESTS ====================

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENotOwner)]
fun test_set_staking_vault_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(USER1); // Switch to unauthorized user
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Should fail - USER1 is not admin
    staking_rewards_distributor::set_staking_vault(&mut distributor, STAKING_VAULT, ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidZeroAddress)]
fun test_set_staking_vault_zero_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Should fail - zero address not allowed
    staking_rewards_distributor::set_staking_vault(&mut distributor, @0x0, ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENotOwner)]
fun test_approve_assets_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(USER1); // Switch to unauthorized user
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    let assets = vector[@0x123];
    
    // Should fail - USER1 is not admin
    staking_rewards_distributor::approve_assets(&mut distributor, assets, ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENoAssetsProvided)]
fun test_approve_empty_assets() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Should fail - empty assets vector
    staking_rewards_distributor::approve_assets(&mut distributor, vector::empty<address>(), ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENotOwner)]
fun test_revoke_approvals_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(USER1); // Switch to unauthorized user
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    let assets = vector[@0x123];
    
    // Should fail - USER1 is not admin
    staking_rewards_distributor::revoke_approvals(&mut distributor, assets, @0x456, ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENoAssetsProvided)]
fun test_revoke_empty_assets() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Should fail - empty assets vector
    staking_rewards_distributor::revoke_approvals(&mut distributor, vector::empty<address>(), @0x456, ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidZeroAddress)]
fun test_revoke_approvals_zero_target() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    let assets = vector[@0x123];
    
    // Should fail - zero target address
    staking_rewards_distributor::revoke_approvals(&mut distributor, assets, @0x0, ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidZeroAddress)]
fun test_transfer_admin_zero_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Should fail - zero address not allowed as new admin
    staking_rewards_distributor::transfer_admin(&mut distributor, @0x0, ts.ctx());
    
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::ENotOwner)]
fun test_rescue_generic_tokens_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let distributor = ts.take_shared<StakingRewardsDistributor>();
    let mut token_balance = staking_rewards_distributor::create_token_balance<TestToken>(ts.ctx());
    
    let test_coin = coin::mint_for_testing<TestToken>(500, ts.ctx());
    staking_rewards_distributor::add_token_balance(&mut token_balance, test_coin);
    
    ts.next_tx(USER1); // Switch to unauthorized user
    
    // Should fail - USER1 is not admin
    let _rescued_coin = staking_rewards_distributor::rescue_tokens(
        &distributor, &mut token_balance, 100, USER1, ts.ctx()
    );
    
    coin::burn_for_testing(_rescued_coin);
    transfer::public_transfer(token_balance, ADMIN);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidZeroAddress)]
fun test_rescue_generic_tokens_zero_recipient() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let distributor = ts.take_shared<StakingRewardsDistributor>();
    let mut token_balance = staking_rewards_distributor::create_token_balance<TestToken>(ts.ctx());
    
    let test_coin = coin::mint_for_testing<TestToken>(500, ts.ctx());
    staking_rewards_distributor::add_token_balance(&mut token_balance, test_coin);
    
    // Should fail - zero recipient address
    let _rescued_coin = staking_rewards_distributor::rescue_tokens(
        &distributor, &mut token_balance, 100, @0x0, ts.ctx()
    );
    
    coin::burn_for_testing(_rescued_coin);
    transfer::public_transfer(token_balance, ADMIN);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
#[expected_failure(abort_code = elixir::staking_rewards_distributor::EInvalidAmount)]
fun test_rescue_generic_tokens_zero_amount() {
    let mut ts = test_scenario::begin(ADMIN);
    
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let distributor = ts.take_shared<StakingRewardsDistributor>();
    let mut token_balance = staking_rewards_distributor::create_token_balance<TestToken>(ts.ctx());
    
    let test_coin = coin::mint_for_testing<TestToken>(500, ts.ctx());
    staking_rewards_distributor::add_token_balance(&mut token_balance, test_coin);
    
    // Should fail - zero amount
    let _rescued_coin = staking_rewards_distributor::rescue_tokens(
        &distributor, &mut token_balance, 0, USER1, ts.ctx()
    );
    
    coin::burn_for_testing(_rescued_coin);
    transfer::public_transfer(token_balance, ADMIN);
    test_scenario::return_shared(distributor);
    ts.end();
}

#[test]
fun test_transfer_rewards_exact_balance() {
    let mut ts = test_scenario::begin(ADMIN);
    
    // Initialize deUSD first
    deusd::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<deusd::Management>();
    
    // Mint exact amount
    let deusd_coin = deusd::mint(&mut management, USER1, 500, ts.ctx());
    
    // Initialize distributor
    staking_rewards_distributor::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut distributor = ts.take_shared<StakingRewardsDistributor>();
    
    // Set operator and add balance
    staking_rewards_distributor::set_operator(&mut distributor, OPERATOR, ts.ctx());
    staking_rewards_distributor::add_deusd_balance(&mut distributor, deusd_coin);
    
    ts.next_tx(OPERATOR);
    
    // Transfer exact balance
    let reward_coin = staking_rewards_distributor::transfer_in_rewards(&mut distributor, 500, ts.ctx());
    
    assert!(coin::value(&reward_coin) == 500, 0);
    assert!(staking_rewards_distributor::get_deusd_balance(&distributor) == 0, 1);
    
    coin::burn_for_testing(reward_coin);
    test_scenario::return_shared(distributor);
    test_scenario::return_shared(management);
    ts.end();
}
