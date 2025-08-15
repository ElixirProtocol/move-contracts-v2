#[test_only]
module elixir::deusd_minting_tests;

use elixir::test_utils;
use elixir::deusd_minting::{Self, DeUSDMintingManagement};
use elixir::admin_cap::{Self as admin_cap, AdminCap};
use elixir::config::{Self, GlobalConfig};
use elixir::deusd::{DeUSDConfig};
use elixir::roles;
use sui::test_scenario;
use sui::test_utils::assert_eq;
use sui::test_scenario::Scenario;

// Test constants
const ADMIN: address = @0xad;
const MINTER: address = @0xBB;
const REDEEMER: address = @0xCC;
const CUSTODIAN1: address = @0xC1;
const CUSTODIAN2: address = @0xC2;
const ALICE: address = @0xa11ce;
const GATEKEEPER: address = @0xfeed;

const MAX_U64: u64 = 18446744073709551615;

public struct ETH has drop {}

public struct USDC has drop {}

#[test]
fun test_initialization() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize the management with basic parameters
    let custodians = vector[CUSTODIAN1, CUSTODIAN2];

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        custodians,
        1000000,
        1000000,
    );

    // Test basic initialization
    assert_eq(1000000, deusd_minting::get_max_mint_per_block(&management));
    assert_eq(1000000, deusd_minting::get_max_redeem_per_block(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_add_supported_asset() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Test adding supported asset using type parameter
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 0);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_remove_supported_asset() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Add then remove asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 0);

    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    assert!(!deusd_minting::is_supported_asset<ETH>(&management), 1);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_add_custodian_address() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Test adding custodian address
    deusd_minting::add_custodian_address(&admin_cap, &mut management, &global_config, CUSTODIAN2);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_remove_custodian_address() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize with custodians
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1, CUSTODIAN2],
        1000000,
        500000,
    );

    // Remove custodian
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, &global_config, CUSTODIAN2);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_set_max_mint_per_second() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Set new max mint per second
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, &global_config, 2000000);
    assert_eq(2000000, deusd_minting::get_max_mint_per_block(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_set_max_redeem_per_second() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Set new max redeem per second
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, &global_config, 1500000);
    assert_eq(1500000, deusd_minting::get_max_redeem_per_block(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_disable_mint_redeem() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant gatekeeper role and disable
    config::add_role(&admin_cap, &mut global_config, GATEKEEPER, roles::role_gate_keeper());

    ts.next_tx(GATEKEEPER);
    deusd_minting::disable_mint_redeem(&mut management, &global_config, ts.ctx());

    // Both limits should be set to 0
    assert_eq(0, deusd_minting::get_max_mint_per_block(&management));
    assert_eq(0, deusd_minting::get_max_redeem_per_block(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_verify_route() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize with custodians
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1, CUSTODIAN2],
        1000000,
        500000,
    );

    // Test valid route
    let _addresses = vector[CUSTODIAN1, CUSTODIAN2];

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_hash_order() {
    let ts = test_scenario::begin(ADMIN);

    // Test hash consistency with new signature
    let hash1 = deusd_minting::hash_order<ETH>(
        0, // order_type
        1000000, // expiry
        1, // nonce
        ALICE, // benefactor
        ALICE, // beneficiary
        1000, // collateral_amount
        1000, // deusd_amount
    );

    let hash2 = deusd_minting::hash_order<ETH>(
        0, // order_type
        1000000, // expiry
        1, // nonce
        ALICE, // benefactor
        ALICE, // beneficiary
        1000, // collateral_amount
        1000, // deusd_amount
    );

    let hash3 = deusd_minting::hash_order<ETH>(
        0, // order_type
        1000000, // expiry
        2, // different nonce
        ALICE, // benefactor
        ALICE, // beneficiary
        1000, // collateral_amount
        1000, // deusd_amount
    );

    // Same orders should have same hash
    assert!(hash1 == hash2, 0);

    // Different orders should have different hashes
    assert!(hash1 != hash3, 1);

    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidCustodianAddress)]
fun test_add_custodian_address_fail_if_zero_address() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // This should fail because zero address is invalid
    deusd_minting::add_custodian_address(&admin_cap, &mut management, &global_config, @0x0);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_operations_fail_if_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Try to add asset without initialization - should fail
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// ===== COMPREHENSIVE EDGE CASE TESTS =====

#[test]
#[expected_failure(abort_code = deusd_minting::EInitialized)]
fun test_initialize_twice_fails() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first time
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Try to initialize again - should fail
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN2],
        2000000,
        1000000,
    );

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_multiple_asset_support() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Add multiple assets
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    deusd_minting::add_supported_asset<USDC>(&admin_cap, &mut management, &global_config);

    // Verify both assets are supported
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 0);
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 1);

    // Remove one asset
    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management, &global_config);

    // Verify only one asset remains
    assert!(!deusd_minting::is_supported_asset<ETH>(&management), 2);
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 3);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_remove_asset_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Try to remove asset without initialization - should fail
    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management, &global_config);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_custodian_operations_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Try to add custodian without initialization - should fail
    deusd_minting::add_custodian_address(&admin_cap, &mut management, &global_config, CUSTODIAN1);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_remove_custodian_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Try to remove custodian without initialization - should fail
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, &global_config, CUSTODIAN1);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_set_max_mint_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Try to set max mint without initialization - should fail
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, &global_config, 2000000);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_set_max_redeem_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Try to set max redeem without initialization - should fail
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, &global_config, 1000000);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_multiple_custodian_management() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize with one custodian
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Add multiple custodians
    deusd_minting::add_custodian_address(&admin_cap, &mut management, &global_config, CUSTODIAN2);
    deusd_minting::add_custodian_address(&admin_cap, &mut management, &global_config, ALICE);

    // Remove one custodian
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, &global_config, ALICE);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_extreme_limit_values() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Test setting very high limits
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, &global_config, MAX_U64);
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, &global_config, MAX_U64);

    assert_eq(MAX_U64, deusd_minting::get_max_mint_per_block(&management));
    assert_eq(MAX_U64, deusd_minting::get_max_redeem_per_block(&management));

    // Test setting to zero
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, &global_config, 0);
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, &global_config, 0);

    assert_eq(0, deusd_minting::get_max_mint_per_block(&management));
    assert_eq(0, deusd_minting::get_max_redeem_per_block(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_hash_order_different_types() {
    let ts = test_scenario::begin(ADMIN);

    // Test hash for different collateral types
    let hash_eth = deusd_minting::hash_order<ETH>(
        0, // order_type
        1000000, // expiry
        1, // nonce
        ALICE, // benefactor
        ALICE, // beneficiary
        1000, // collateral_amount
        1000, // deusd_amount
    );

    let hash_usdc = deusd_minting::hash_order<USDC>(
        0, // order_type
        1000000, // expiry
        1, // nonce
        ALICE, // benefactor
        ALICE, // beneficiary
        1000, // collateral_amount
        1000, // deusd_amount
    );

    // Different types should produce different hashes
    assert!(hash_eth != hash_usdc, 0);

    // Test hash for different order types
    let hash_mint = deusd_minting::hash_order<ETH>(
        0, // MINT
        1000000, // expiry
        1, // nonce
        ALICE, // benefactor
        ALICE, // beneficiary
        1000, // collateral_amount
        1000, // deusd_amount
    );

    let hash_redeem = deusd_minting::hash_order<ETH>(
        1, // REDEEM
        1000000, // expiry
        1, // nonce
        ALICE, // benefactor
        ALICE, // beneficiary
        1000, // collateral_amount
        1000, // deusd_amount
    );

    // Different order types should produce different hashes
    assert!(hash_mint != hash_redeem, 1);

    ts.end();
}

#[test]
fun test_role_grant_comprehensive() {
    let (ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant all different roles to different addresses using ACL
    config::add_role(&admin_cap, &mut global_config, MINTER, roles::role_minter());
    config::add_role(&admin_cap, &mut global_config, REDEEMER, roles::role_redeemer());
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_collateral_manager());
    config::add_role(&admin_cap, &mut global_config, GATEKEEPER, roles::role_gate_keeper());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_disable_mint_redeem_unauthorized() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    ts.next_tx(ALICE); // ALICE is not a gatekeeper
    // Try to disable mint/redeem without gatekeeper role - should fail
    deusd_minting::disable_mint_redeem(&mut management, &global_config, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// ===== ADDITIONAL COMPREHENSIVE TESTS FOR MISSING COVERAGE =====

#[test]
fun test_remove_minter_role() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant minter and gatekeeper roles using ACL
    config::add_role(&admin_cap, &mut global_config, MINTER, roles::role_minter());
    config::add_role(&admin_cap, &mut global_config, GATEKEEPER, roles::role_gate_keeper());

    ts.next_tx(GATEKEEPER);
    // Remove minter role
    deusd_minting::remove_minter_role(&mut management, &mut global_config, MINTER, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_remove_redeemer_role() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant redeemer and gatekeeper roles using ACL
    config::add_role(&admin_cap, &mut global_config, REDEEMER, roles::role_redeemer());
    config::add_role(&admin_cap, &mut global_config, GATEKEEPER, roles::role_gate_keeper());

    ts.next_tx(GATEKEEPER);
    deusd_minting::remove_redeemer_role(&mut management, &mut global_config, REDEEMER, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_remove_collateral_manager_role() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager and gatekeeper roles using ACL
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_collateral_manager());
    config::add_role(&admin_cap, &mut global_config, GATEKEEPER, roles::role_gate_keeper());

    ts.next_tx(GATEKEEPER);
    // Remove collateral manager role
    deusd_minting::remove_collateral_manager_role(&mut management, &mut global_config, ALICE, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_remove_minter_role_unauthorized() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant minter role
    config::add_role(&admin_cap, &mut global_config, MINTER, roles::role_minter());

    ts.next_tx(ALICE); // ALICE is not a gatekeeper
    // Try to remove minter role without gatekeeper role - should fail
    deusd_minting::remove_minter_role(&mut management, &mut global_config, MINTER, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_verify_route_invalid_scenarios() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize with custodians
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1, CUSTODIAN2],
        1000000,
        500000,
    );

    // Test empty route - should fail
    let empty_addresses = vector::empty<address>();
    let empty_ratios = vector::empty<u64>();
    let custodian_addresses = deusd_minting::get_custodian_addresses_for_test(&management);
    assert!(!deusd_minting::verify_route(empty_addresses, empty_ratios, custodian_addresses), 0);

    // Test mismatched lengths - should fail
    let addresses1 = vector[CUSTODIAN1, CUSTODIAN2];
    let ratios1 = vector[10000]; // Only one ratio for two addresses
    assert!(!deusd_minting::verify_route(addresses1, ratios1, custodian_addresses), 1);

    // Test invalid custodian - should fail
    let addresses2 = vector[ALICE]; // ALICE is not a custodian
    let ratios2 = vector[10000];
    assert!(!deusd_minting::verify_route(addresses2, ratios2, custodian_addresses), 2);

    // Test zero address - should fail
    let addresses3 = vector[@0x0];
    let ratios3 = vector[10000];
    assert!(!deusd_minting::verify_route(addresses3, ratios3, custodian_addresses), 3);

    // Test zero ratio - should fail
    let addresses4 = vector[CUSTODIAN1];
    let ratios4 = vector[0];
    assert!(!deusd_minting::verify_route(addresses4, ratios4, custodian_addresses), 4);

    // Test incorrect total ratio - should fail
    let addresses5 = vector[CUSTODIAN1, CUSTODIAN2];
    let ratios5 = vector[5000, 4000]; // Total = 9000, not 10000
    assert!(!deusd_minting::verify_route(addresses5, ratios5, custodian_addresses), 5);

    // Test valid route - should pass
    let addresses6 = vector[CUSTODIAN1, CUSTODIAN2];
    let ratios6 = vector[6000, 4000]; // Total = 10000
    assert!(deusd_minting::verify_route(addresses6, ratios6, custodian_addresses), 6);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_is_supported_asset() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Initially no assets should be supported
    assert!(!deusd_minting::is_supported_asset<ETH>(&management), 0);
    assert!(!deusd_minting::is_supported_asset<USDC>(&management), 1);

    // Add ETH and verify
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 2);
    assert!(!deusd_minting::is_supported_asset<USDC>(&management), 3);

    // Add USDC and verify both
    deusd_minting::add_supported_asset<USDC>(&admin_cap, &mut management, &global_config);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 4);
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 5);

    // Remove ETH and verify
    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    assert!(!deusd_minting::is_supported_asset<ETH>(&management), 6);
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 7);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_max_limits_getters() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize with specific limits
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1500000, // max_mint_per_second
        750000, // max_redeem_per_second
    );

    // Test getters return correct values
    assert_eq(1500000, deusd_minting::get_max_mint_per_block(&management));
    assert_eq(750000, deusd_minting::get_max_redeem_per_block(&management));

    // Update limits and test again
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, &global_config, 2000000);
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, &global_config, 1000000);

    assert_eq(2000000, deusd_minting::get_max_mint_per_block(&management));
    assert_eq(1000000, deusd_minting::get_max_redeem_per_block(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_hash_order_edge_cases() {
    let ts = test_scenario::begin(ADMIN);

    // Test with maximum values
    let hash_max = deusd_minting::hash_order<ETH>(
        255, // max u8
        18446744073709551615, // max u64 expiry
        18446744073709551615, // max u64 nonce
        @0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, // max address
        @0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        18446744073709551615, // max u64 collateral_amount
        18446744073709551615, // max u64 deusd_amount
    );

    // Test with minimum values
    let hash_min = deusd_minting::hash_order<ETH>(
        0, // min u8
        0, // min u64 expiry
        1, // min valid nonce (0 would be invalid in real usage)
        @0x1, // min non-zero address
        @0x1,
        1, // min collateral_amount
        1, // min deusd_amount
    );

    // Different inputs should produce different hashes
    assert!(hash_max != hash_min, 0);

    // Test with same values produces same hash
    let hash_max2 = deusd_minting::hash_order<ETH>(
        255,
        18446744073709551615,
        18446744073709551615,
        @0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        @0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        18446744073709551615,
        18446744073709551615,
    );

    assert!(hash_max == hash_max2, 1);

    ts.end();
}

#[test]
fun test_custodian_edge_cases() {
    let (ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize with many custodians
    let many_custodians = vector[
        CUSTODIAN1, CUSTODIAN2, ALICE, MINTER, REDEEMER, GATEKEEPER,
        @0x111, @0x222, @0x333, @0x444
    ];

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        many_custodians,
        1000000,
        500000,
    );

    // Add another custodian
    deusd_minting::add_custodian_address(&admin_cap, &mut management, &global_config, @0x555);

    // Remove multiple custodians
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, &global_config, ALICE);
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, &global_config, @0x111);
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, &global_config, @0x222);

    // Test route with remaining custodians
    let addresses = vector[CUSTODIAN1, CUSTODIAN2, MINTER];
    let ratios = vector[3000, 3000, 4000]; // 30%, 30%, 40%
    let custodian_addresses = deusd_minting::get_custodian_addresses_for_test(&management);
    assert!(deusd_minting::verify_route(addresses, ratios, custodian_addresses), 0);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_transfer_to_custody() {
    let (ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager role to ALICE using ACL
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_collateral_manager());

    // Add ETH as supported asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_transfer_to_custody_unauthorized() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Add ETH as supported asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);


    ts.next_tx(ALICE); // ALICE is not a collateral manager
    // Try to transfer to custody without collateral manager role - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, &global_config, CUSTODIAN1, 1000, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAddress)]
fun test_transfer_to_custody_zero_address() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager role to ALICE
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_collateral_manager());

    // Add ETH as supported asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);

    ts.next_tx(ALICE);
    // Try to transfer to zero address - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, &global_config, @0x0, 1000, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAddress)]
fun test_transfer_to_custody_invalid_custodian() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager role to ALICE
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_collateral_manager());

    // Add ETH as supported asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);

    ts.next_tx(ALICE);
    // Try to transfer to address that is not a custodian - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, &global_config, MINTER, 1000, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_transfer_to_custody_not_initialized() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    ts.next_tx(ALICE);
    // Try to transfer to custody without initialization - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, &global_config, CUSTODIAN1, 1000, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
fun test_collateral_manager_authorization() {
    let (mut ts, mut global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1, CUSTODIAN2],
        1000000,
        500000,
    );

    // Grant collateral manager role to multiple addresses
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_collateral_manager());
    config::add_role(&admin_cap, &mut global_config, MINTER, roles::role_collateral_manager());

    // Add assets
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    deusd_minting::add_supported_asset<USDC>(&admin_cap, &mut management, &global_config);

    // Grant gatekeeper role to remove collateral managers later
    config::add_role(&admin_cap, &mut global_config, GATEKEEPER, roles::role_gate_keeper());

    // Remove one collateral manager
    ts.next_tx(GATEKEEPER);
    deusd_minting::remove_collateral_manager_role(&mut management, &mut global_config, ALICE, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

// === Helper Functions ===

public fun setup_test(): (Scenario, GlobalConfig, AdminCap, DeUSDConfig, DeUSDMintingManagement) {
    let mut ts = test_scenario::begin(ADMIN);

    let (global_config, admin_cap) = test_utils::setup_global_config(&mut ts, ADMIN);
    let deusd_config = test_utils::setup_deusd(&mut ts, ADMIN);
    let deusd_minting_management = test_utils::setup_deusd_minting(&mut ts, ADMIN);

    (ts, global_config, admin_cap, deusd_config, deusd_minting_management)
}

public fun clean_test(
    ts: Scenario,
    global_config: GlobalConfig, 
    admin_cap: AdminCap,
    deusd_config: DeUSDConfig,
    management: DeUSDMintingManagement,
) {
    test_scenario::return_shared(global_config);
    admin_cap::destroy_for_test(admin_cap);
    test_scenario::return_shared(deusd_config);
    test_scenario::return_shared(management);
    ts.end();
}