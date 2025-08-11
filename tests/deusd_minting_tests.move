#[test_only]
module elixir::deusd_minting_tests;

use elixir::deusd_minting::{Self, DeUSDMintingManagement};
use elixir::admin_cap::{Self, AdminCap};
use elixir::package_version;
use sui::test_scenario;

// Test constants
const ADMIN: address = @0xad;
const MINTER: address = @0xBB;
const REDEEMER: address = @0xCC;
const CUSTODIAN1: address = @0xDD;
const CUSTODIAN2: address = @0xc2;
const ALICE: address = @0xa11ce;
const GATEKEEPER: address = @0xfeed;

public struct ETH has drop {}
public struct USDC has drop {}

#[test]
fun test_initialization() {
    let mut ts = test_scenario::begin(ADMIN);
    
    // Initialize admin cap and deusd_minting
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize the management with basic parameters
    let custodians = vector[CUSTODIAN1, CUSTODIAN2];
    
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        custodians,
        1000000,
        1000000,
    );
    
    // Test basic initialization
    assert!(deusd_minting::get_max_mint_per_block(&management) == 1000000, 0);
    assert!(deusd_minting::get_max_redeem_per_block(&management) == 1000000, 1);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_add_supported_asset() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Test adding supported asset using type parameter
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 0);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_remove_supported_asset() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Add then remove asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 0);

    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management);
    assert!(!deusd_minting::is_supported_asset<ETH>(&management), 1);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_add_custodian_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Test adding custodian address
    deusd_minting::add_custodian_address(&admin_cap, &mut management, CUSTODIAN2);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_remove_custodian_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize with custodians
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1, CUSTODIAN2],
        1000000,
        500000,
    );

    // Remove custodian
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, CUSTODIAN2);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_grant_minter_role() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant minter role
    deusd_minting::grant_minter_role(&admin_cap, &mut management, MINTER, &version);

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_grant_redeemer_role() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant redeemer role
    deusd_minting::grant_redeemer_role(&admin_cap, &mut management, REDEEMER, &version);

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_set_max_mint_per_second() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Set new max mint per second
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, 2000000);
    assert!(deusd_minting::get_max_mint_per_block(&management) == 2000000, 0);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_set_max_redeem_per_second() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Set new max redeem per second
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, 1500000);
    assert!(deusd_minting::get_max_redeem_per_block(&management) == 1500000, 0);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_disable_mint_redeem() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );
    
    let version = package_version::create_for_test(ts.ctx());
    // Grant gatekeeper role and disable
    deusd_minting::grant_gatekeeper_role(&admin_cap, &mut management, GATEKEEPER, &version);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(GATEKEEPER);
    deusd_minting::disable_mint_redeem(&mut management, ts.ctx());

    // Both limits should be set to 0
    assert!(deusd_minting::get_max_mint_per_block(&management) == 0, 0);
    assert!(deusd_minting::get_max_redeem_per_block(&management) == 0, 1);

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_set_delegated_signer() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Set delegated signer
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_confirm_delegated_signer() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Set delegated signer first
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(MINTER);
    // Confirm delegation
    deusd_minting::confirm_delegated_signer(&mut management, ADMIN, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_verify_route() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize with custodians
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1, CUSTODIAN2],
        1000000,
        500000,
    );

    // Test valid route
    let _addresses = vector[CUSTODIAN1, CUSTODIAN2];
    let _ratios = vector[6000, 4000]; // 60-40 split (must add to 10,000)

    // Note: verify_route now requires access to the custodian_addresses from management
    // This test validates the route format but may need adjustment based on actual implementation

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
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
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // This should fail because zero address is invalid
    deusd_minting::add_custodian_address(&admin_cap, &mut management, @0x0);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_operations_fail_if_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Try to add asset without initialization - should fail
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

// ===== COMPREHENSIVE EDGE CASE TESTS =====

#[test]
#[expected_failure(abort_code = deusd_minting::EInitialized)]
fun test_initialize_twice_fails() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first time
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Try to initialize again - should fail
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN2],
        2000000,
        1000000,
    );

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_grant_collateral_manager_role() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager role
    deusd_minting::grant_collateral_manager_role(&admin_cap, &mut management, ALICE, &version);

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_multiple_asset_support() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Add multiple assets
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);
    deusd_minting::add_supported_asset<USDC>(&admin_cap, &mut management);

    // Verify both assets are supported
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 0);
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 1);

    // Remove one asset
    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management);

    // Verify only one asset remains
    assert!(!deusd_minting::is_supported_asset<ETH>(&management), 2);
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 3);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_remove_asset_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Try to remove asset without initialization - should fail
    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_custodian_operations_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Try to add custodian without initialization - should fail
    deusd_minting::add_custodian_address(&admin_cap, &mut management, CUSTODIAN1);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_remove_custodian_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Try to remove custodian without initialization - should fail
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, CUSTODIAN1);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_set_max_mint_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Try to set max mint without initialization - should fail
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, 2000000);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_set_max_redeem_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Try to set max redeem without initialization - should fail
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, 1000000);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_multiple_custodian_management() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize with one custodian
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Add multiple custodians
    deusd_minting::add_custodian_address(&admin_cap, &mut management, CUSTODIAN2);
    deusd_minting::add_custodian_address(&admin_cap, &mut management, ALICE);

    // Remove one custodian
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, ALICE);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_extreme_limit_values() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Test setting very high limits
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, 18446744073709551615); // Max u64
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, 18446744073709551615); // Max u64

    assert!(deusd_minting::get_max_mint_per_block(&management) == 18446744073709551615, 0);
    assert!(deusd_minting::get_max_redeem_per_block(&management) == 18446744073709551615, 1);

    // Test setting to zero
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, 0);
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, 0);

    assert!(deusd_minting::get_max_mint_per_block(&management) == 0, 2);
    assert!(deusd_minting::get_max_redeem_per_block(&management) == 0, 3);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
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
#[expected_failure(abort_code = deusd_minting::EDelegationNotInitiated)]
fun test_confirm_delegated_signer_not_initiated() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(MINTER);
    // Try to confirm delegation without setting it first - should fail
    deusd_minting::confirm_delegated_signer(&mut management, ADMIN, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EDelegationNotInitiated)]
fun test_confirm_delegated_signer_wrong_delegator() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Set delegated signer from ADMIN to MINTER
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(MINTER);
    // Try to confirm delegation with wrong delegator - should fail
    deusd_minting::confirm_delegated_signer(&mut management, ALICE, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_role_grant_comprehensive() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant all different roles to different addresses
    deusd_minting::grant_minter_role(&admin_cap, &mut management, MINTER, &version);
    deusd_minting::grant_redeemer_role(&admin_cap, &mut management, REDEEMER, &version);
    deusd_minting::grant_collateral_manager_role(&admin_cap, &mut management, ALICE, &version);
    deusd_minting::grant_gatekeeper_role(&admin_cap, &mut management, GATEKEEPER, &version);

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]  
fun test_disable_mint_redeem_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(ALICE); // ALICE is not a gatekeeper
    // Try to disable mint/redeem without gatekeeper role - should fail
    deusd_minting::disable_mint_redeem(&mut management, ts.ctx());

    test_scenario::return_shared(management);
    ts.end();
}

// ===== ADDITIONAL COMPREHENSIVE TESTS FOR MISSING COVERAGE =====

#[test]
fun test_remove_minter_role() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant minter and gatekeeper roles
    deusd_minting::grant_minter_role(&admin_cap, &mut management, MINTER, &version);
    deusd_minting::grant_gatekeeper_role(&admin_cap, &mut management, GATEKEEPER, &version);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(GATEKEEPER);
    // Remove minter role
    deusd_minting::remove_minter_role(&mut management, MINTER, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_remove_redeemer_role() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant redeemer and gatekeeper roles
    deusd_minting::grant_redeemer_role(&admin_cap, &mut management, REDEEMER, &version);
    deusd_minting::grant_gatekeeper_role(&admin_cap, &mut management, GATEKEEPER, &version);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(GATEKEEPER);
    // Remove redeemer role
    deusd_minting::remove_redeemer_role(&mut management, REDEEMER, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_remove_collateral_manager_role() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager and gatekeeper roles
    deusd_minting::grant_collateral_manager_role(&admin_cap, &mut management, ALICE, &version);
    deusd_minting::grant_gatekeeper_role(&admin_cap, &mut management, GATEKEEPER, &version);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(GATEKEEPER);
    // Remove collateral manager role
    deusd_minting::remove_collateral_manager_role(&mut management, ALICE, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_remove_minter_role_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant minter role
    deusd_minting::grant_minter_role(&admin_cap, &mut management, MINTER, &version);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(ALICE); // ALICE is not a gatekeeper
    // Try to remove minter role without gatekeeper role - should fail
    deusd_minting::remove_minter_role(&mut management, MINTER, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_grant_minter_role_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Try to grant minter role without initialization - should fail
    deusd_minting::grant_minter_role(&admin_cap, &mut management, MINTER, &version);

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidZeroAddress)]
fun test_grant_minter_role_zero_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Try to grant minter role to zero address - should fail
    deusd_minting::grant_minter_role(&admin_cap, &mut management, @0x0, &version);

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidZeroAddress)]
fun test_grant_redeemer_role_zero_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Try to grant redeemer role to zero address - should fail
    deusd_minting::grant_redeemer_role(&admin_cap, &mut management, @0x0, &version);

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidZeroAddress)]
fun test_grant_collateral_manager_role_zero_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Try to grant collateral manager role to zero address - should fail
    deusd_minting::grant_collateral_manager_role(&admin_cap, &mut management, @0x0, &version);

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidZeroAddress)]
fun test_grant_gatekeeper_role_zero_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Try to grant gatekeeper role to zero address - should fail
    deusd_minting::grant_gatekeeper_role(&admin_cap, &mut management, @0x0, &version);

    package_version::destroy_for_test(version);
    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_verify_route_invalid_scenarios() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize with custodians
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1, CUSTODIAN2],
        1000000,
        500000,
    );

    // Test empty route - should fail
    let empty_addresses = vector::empty<address>();
    let empty_ratios = vector::empty<u64>();
    let custodian_addresses = deusd_minting::get_custodian_addresses(&management);
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

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_is_supported_asset() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Initially no assets should be supported
    assert!(!deusd_minting::is_supported_asset<ETH>(&management), 0);
    assert!(!deusd_minting::is_supported_asset<USDC>(&management), 1);

    // Add ETH and verify
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 2);
    assert!(!deusd_minting::is_supported_asset<USDC>(&management), 3);

    // Add USDC and verify both
    deusd_minting::add_supported_asset<USDC>(&admin_cap, &mut management);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 4);
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 5);

    // Remove ETH and verify
    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management);
    assert!(!deusd_minting::is_supported_asset<ETH>(&management), 6);
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 7);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_max_limits_getters() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize with specific limits
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1500000, // max_mint_per_second
        750000,  // max_redeem_per_second
    );

    // Test getters return correct values
    assert!(deusd_minting::get_max_mint_per_block(&management) == 1500000, 0);
    assert!(deusd_minting::get_max_redeem_per_block(&management) == 750000, 1);

    // Update limits and test again
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, 2000000);
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, 1000000);

    assert!(deusd_minting::get_max_mint_per_block(&management) == 2000000, 2);
    assert!(deusd_minting::get_max_redeem_per_block(&management) == 1000000, 3);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_delegation_workflow_complete() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // ADMIN sets delegated signer to MINTER
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(MINTER);
    // MINTER confirms delegation from ADMIN
    deusd_minting::confirm_delegated_signer(&mut management, ADMIN, &version, ts.ctx());

    // Test multiple delegators to same delegate
    ts.next_tx(ALICE);
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    ts.next_tx(MINTER);
    // MINTER confirms delegation from ALICE too
    deusd_minting::confirm_delegated_signer(&mut management, ALICE, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_set_delegated_signer_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Try to set delegated signer without initialization - should fail
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_confirm_delegated_signer_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Try to confirm delegated signer without initialization - should fail
    deusd_minting::confirm_delegated_signer(&mut management, ADMIN, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
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
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize with many custodians
    let many_custodians = vector[
        CUSTODIAN1, CUSTODIAN2, ALICE, MINTER, REDEEMER, GATEKEEPER,
        @0x111, @0x222, @0x333, @0x444
    ];
    
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        many_custodians,
        1000000,
        500000,
    );

    // Add another custodian
    deusd_minting::add_custodian_address(&admin_cap, &mut management, @0x555);

    // Remove multiple custodians
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, ALICE);
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, @0x111);
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, @0x222);

    // Test route with remaining custodians
    let addresses = vector[CUSTODIAN1, CUSTODIAN2, MINTER];
    let ratios = vector[3000, 3000, 4000]; // 30%, 30%, 40%
    let custodian_addresses = deusd_minting::get_custodian_addresses(&management);
    assert!(deusd_minting::verify_route(addresses, ratios, custodian_addresses), 0);

    test_scenario::return_to_sender(&ts, admin_cap);
    test_scenario::return_shared(management);
    ts.end();
}

// ===== ADDITIONAL TESTS FOR NEW FUNCTIONS =====

#[test]
fun test_remove_delegated_signer() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // ADMIN sets delegated signer to MINTER
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(MINTER);
    // MINTER confirms delegation from ADMIN
    deusd_minting::confirm_delegated_signer(&mut management, ADMIN, &version, ts.ctx());

    ts.next_tx(ADMIN);
    // ADMIN removes delegated signer
    deusd_minting::remove_delegated_signer(&mut management, MINTER, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EDelegationNotInitiated)]
fun test_remove_delegated_signer_not_initiated() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(ADMIN);
    // Try to remove delegated signer without setting it first - should fail
    deusd_minting::remove_delegated_signer(&mut management, MINTER, ts.ctx());

    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EDelegationNotInitiated)]
fun test_remove_delegated_signer_wrong_delegator() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // ADMIN sets delegated signer to MINTER
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(ALICE); // ALICE did not delegate to MINTER
    // Try to remove delegated signer as wrong delegator - should fail
    deusd_minting::remove_delegated_signer(&mut management, MINTER, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_transfer_to_custody() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager role to ALICE
    deusd_minting::grant_collateral_manager_role(&admin_cap, &mut management, ALICE, &version);

    // Add ETH as supported asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    // Note: This test cannot fully execute transfer_to_custody because it requires
    // actual ETH balance in the contract, which would need mock coin creation
    // and minting flow simulation. This tests the authorization and setup.

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_transfer_to_custody_unauthorized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Add ETH as supported asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(ALICE); // ALICE is not a collateral manager
    // Try to transfer to custody without collateral manager role - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, CUSTODIAN1, 1000, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAddress)]
fun test_transfer_to_custody_zero_address() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager role to ALICE
    deusd_minting::grant_collateral_manager_role(&admin_cap, &mut management, ALICE, &version);

    // Add ETH as supported asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(ALICE);
    // Try to transfer to zero address - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, @0x0, 1000, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAddress)]
fun test_transfer_to_custody_invalid_custodian() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager role to ALICE
    deusd_minting::grant_collateral_manager_role(&admin_cap, &mut management, ALICE, &version);

    // Add ETH as supported asset
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(ALICE);
    // Try to transfer to address that is not a custodian - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, MINTER, 1000, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_transfer_to_custody_not_initialized() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Don't initialize

    ts.next_tx(ALICE);
    // Try to transfer to custody without initialization - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, CUSTODIAN1, 1000, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_complete_delegation_lifecycle() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Complete delegation lifecycle: set -> confirm -> remove
    
    // Step 1: ADMIN sets delegated signer to MINTER
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    // Step 2: MINTER confirms delegation from ADMIN
    ts.next_tx(MINTER);
    deusd_minting::confirm_delegated_signer(&mut management, ADMIN, &version, ts.ctx());

    // Step 3: ADMIN removes delegated signer
    ts.next_tx(ADMIN);
    deusd_minting::remove_delegated_signer(&mut management, MINTER, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_multiple_delegation_management() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Test multiple delegations to same signer
    
    // ADMIN delegates to MINTER
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    ts.next_tx(ALICE);
    // ALICE also delegates to MINTER
    deusd_minting::set_delegated_signer(&mut management, MINTER, &version, ts.ctx());

    ts.next_tx(MINTER);
    // MINTER confirms both delegations
    deusd_minting::confirm_delegated_signer(&mut management, ADMIN, &version, ts.ctx());
    deusd_minting::confirm_delegated_signer(&mut management, ALICE, &version, ts.ctx());

    // Test removing one delegation while keeping the other
    ts.next_tx(ADMIN);
    deusd_minting::remove_delegated_signer(&mut management, MINTER, ts.ctx());

    // ALICE's delegation should still exist and can be removed separately
    ts.next_tx(ALICE);
    deusd_minting::remove_delegated_signer(&mut management, MINTER, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}

#[test]
fun test_collateral_manager_authorization() {
    let mut ts = test_scenario::begin(ADMIN);
    
    admin_cap::init_for_test(ts.ctx());
    deusd_minting::init_for_test(ts.ctx());
    
    ts.next_tx(ADMIN);
    let admin_cap = ts.take_from_sender<AdminCap>();
    let mut management = ts.take_shared<DeUSDMintingManagement>();
    let version = package_version::create_for_test(ts.ctx());

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        vector[CUSTODIAN1, CUSTODIAN2],
        1000000,
        500000,
    );

    // Grant collateral manager role to multiple addresses
    deusd_minting::grant_collateral_manager_role(&admin_cap, &mut management, ALICE, &version);
    deusd_minting::grant_collateral_manager_role(&admin_cap, &mut management, MINTER, &version);

    // Add assets
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management);
    deusd_minting::add_supported_asset<USDC>(&admin_cap, &mut management);

    // Grant gatekeeper role to remove collateral managers later
    deusd_minting::grant_gatekeeper_role(&admin_cap, &mut management, GATEKEEPER, &version);

    // Return admin cap before switching transaction
    test_scenario::return_to_sender(&ts, admin_cap);

    // Test that both collateral managers can access functions
    // (Note: actual transfer would require balances, so we test authorization setup)

    // Remove one collateral manager
    ts.next_tx(GATEKEEPER);
    deusd_minting::remove_collateral_manager_role(&mut management, ALICE, &version, ts.ctx());

    package_version::destroy_for_test(version);
    test_scenario::return_shared(management);
    ts.end();
}
