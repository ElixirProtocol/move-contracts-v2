#[test_only]
module elixir::deusd_minting_tests;

use sui::coin::{Self, Coin};
use sui::test_scenario;
use sui::test_utils::{assert_eq};
use sui::test_scenario::Scenario;
use elixir::locked_funds::LockedFundsManagement;
use elixir::test_utils;
use elixir::deusd_minting::{Self, DeUSDMintingManagement};
use elixir::admin_cap::{Self as admin_cap, AdminCap};
use elixir::config::{Self, GlobalConfig};
use elixir::deusd::{DeUSDConfig};
use elixir::roles;

// === Constants ===

const ADMIN: address = @0xad;
const MINTER: address = @0xBB;
const REDEEMER: address = @0xCC;
const CUSTODIAN1: address = @0xC1;
const CUSTODIAN2: address = @0xC2;
const ALICE: address = @0xa11ce;
const GATEKEEPER: address = @0xfeed;

// === Structs ===

public struct ETH has drop {}

public struct USDC has drop {}

// === Tests ===

#[test]
fun test_initialization() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1, CUSTODIAN2],
        1000000,
        2000000,
    );

    // Test basic initialization
    assert_eq(x"29168617060ffecbc997a42a1d75d4a109f3be2c52ccb4e043dccafccce0e3c1", deusd_minting::get_domain_separator(&management));
    assert_eq(1000000, deusd_minting::get_max_mint_per_second(&management));
    assert_eq(2000000, deusd_minting::get_max_redeem_per_second(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}


#[test]
#[expected_failure(abort_code = deusd_minting::EInitialized)]
fun test_initialize_twice_fail() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

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

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_add_supported_asset_success() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 0);
    // Try adding the same asset again, should not fail
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    assert!(deusd_minting::is_supported_asset<ETH>(&management), 0);

    deusd_minting::add_supported_asset<USDC>(&admin_cap, &mut management, &global_config);
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 0);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_add_supported_asset_fail_if_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    // Try to add asset without initialization - should fail
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_remove_supported_asset_success() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Add assets
    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    deusd_minting::add_supported_asset<USDC>(&admin_cap, &mut management, &global_config);

    // Remove assets
    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    assert!(!deusd_minting::is_supported_asset<ETH>(&management), 1);
    // USDC should still be supported
    assert!(deusd_minting::is_supported_asset<USDC>(&management), 1);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_remove_asset_fail_if_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    // Try to remove asset without initialization - should fail
    deusd_minting::remove_supported_asset<ETH>(&admin_cap, &mut management, &global_config);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_add_custodian_address_success() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    let custodian_addresses = deusd_minting::get_custodian_addresses_for_test(&management);
    assert_eq(custodian_addresses.length(), 1);
    assert!(custodian_addresses.contains(CUSTODIAN1), 0);

    deusd_minting::add_custodian_address(&admin_cap, &mut management, &global_config, CUSTODIAN2);
    let custodian_addresses = deusd_minting::get_custodian_addresses_for_test(&management);
    assert_eq(custodian_addresses.length(), 2);
    assert!(custodian_addresses.contains(CUSTODIAN1), 0);
    assert!(custodian_addresses.contains(CUSTODIAN2), 1);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_add_custodian_address_fail_if_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    // Try to add custodian without initialization - should fail
    deusd_minting::add_custodian_address(&admin_cap, &mut management, &global_config, CUSTODIAN1);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidCustodianAddress)]
fun test_add_custodian_address_fail_if_zero_address() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

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

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_remove_custodian_address_success() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

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
    let custodian_addresses = deusd_minting::get_custodian_addresses_for_test(&management);
    assert_eq(custodian_addresses.length(), 1);
    assert!(custodian_addresses.contains(CUSTODIAN1), 0);
    assert!(!custodian_addresses.contains(CUSTODIAN2), 1);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_remove_custodian_address_fail_if_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    // Try to remove custodian without initialization - should fail
    deusd_minting::remove_custodian_address(&admin_cap, &mut management, &global_config, CUSTODIAN1);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_set_max_mint_per_second_success() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, &global_config, 2000000);
    assert_eq(2000000, deusd_minting::get_max_mint_per_second(&management));

    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, &global_config, 3000000);
    assert_eq(3000000, deusd_minting::get_max_mint_per_second(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_set_max_mint_per_second_fail_if_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    // Try to set max mint without initialization - should fail
    deusd_minting::set_max_mint_per_second(&admin_cap, &mut management, &global_config, 2000000);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_set_max_redeem_per_second_success() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, &global_config, 1500000);
    assert_eq(1500000, deusd_minting::get_max_redeem_per_second(&management));

    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, &global_config, 2500000);
    assert_eq(2500000, deusd_minting::get_max_redeem_per_second(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}


#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_set_max_redeem_per_second_fail_if_not_initialized() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

    // Try to set max redeem without initialization - should fail
    deusd_minting::set_max_redeem_per_second(&admin_cap, &mut management, &global_config, 1000000);

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_disable_mint_redeem_success() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

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

    assert_eq(0, deusd_minting::get_max_mint_per_second(&management));
    assert_eq(0, deusd_minting::get_max_redeem_per_second(&management));

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_disable_mint_redeem_fail_if_not_gatekeeper() {
    let (mut ts, global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // ALICE is not a gatekeeper
    ts.next_tx(ALICE);
    // Try to disable mint/redeem without gatekeeper role - should fail
    deusd_minting::disable_mint_redeem(&mut management, &global_config, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_remove_minter_role_success() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

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

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_remove_minter_role_fail_if_not_gatekeeper() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

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

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_remove_redeemer_role_success() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

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

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_remove_redeemer_role_fail_if_not_gatekeeper() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    // Initialize first
    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant redeemer role
    config::add_role(&admin_cap, &mut global_config, REDEEMER, roles::role_redeemer());

    ts.next_tx(ALICE); // ALICE is not a gatekeeper
    // Try to remove redeemer role without gatekeeper role - should fail
    deusd_minting::remove_redeemer_role(&mut management, &mut global_config, REDEEMER, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_remove_collateral_manager_role_success() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

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

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_remove_collateral_manager_role_fail_if_not_gatekeeper() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    // Grant collateral manager role
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_collateral_manager());

    ts.next_tx(ALICE); // ALICE is not a gatekeeper
    // Try to remove collateral manager role without gatekeeper role - should fail
    deusd_minting::remove_collateral_manager_role(&mut management, &mut global_config, ALICE, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_verify_route_invalid_scenarios() {
    let (ts, global_config, admin_cap, deusd_config,  locked_funds_management, mut management) = setup_test();

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

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_transfer_to_custody_success() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

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

    let eth_amount = 5000000000;
    let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());
    deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

    ts.next_tx(ALICE);
    deusd_minting::transfer_to_custody<ETH>(&mut management, &global_config, CUSTODIAN1, 1000000000, ts.ctx());
    assert_eq(deusd_minting::get_balance<ETH>(&management), 4000000000); // Remaining balance after transfer

    ts.next_tx(ALICE);
    let custody_eth_coin = ts.take_from_address<Coin<ETH>>(CUSTODIAN1);
    assert!(coin::value(&custody_eth_coin) == 1000000000, 0);
    custody_eth_coin.burn_for_testing();

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_transfer_to_custody_fail_if_not_collateral_manager() {
    let (mut ts, global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    let eth_amount = 5000000000;
    let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());
    deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

    // ALICE is not a collateral manager
    ts.next_tx(ALICE);
    // Try to transfer to custody without collateral manager role - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, &global_config, CUSTODIAN1, 1000, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAddress)]
fun test_transfer_to_custody_fail_if_zero_address() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    let eth_amount = 5000000000;
    let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());
    deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

    // Grant collateral manager role to ALICE
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_collateral_manager());

    ts.next_tx(ALICE);
    // Try to transfer to zero address - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, &global_config, @0x0, 1000, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAddress)]
fun test_transfer_to_custody_fail_if_invalid_custodian() {
    let (mut ts, mut global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    let eth_amount = 5000000000;
    let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());
    deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

    // Grant collateral manager role to ALICE
    config::add_role(&admin_cap, &mut global_config, ALICE, roles::role_collateral_manager());

    ts.next_tx(ALICE);
    // Try to transfer to address that is not a custodian - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, &global_config, MINTER, 1000, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_transfer_to_custody_fail_if_not_initialized() {
    let (mut ts, global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    ts.next_tx(ALICE);
    // Try to transfer to custody without initialization - should fail
    deusd_minting::transfer_to_custody<ETH>(&mut management, &global_config, CUSTODIAN1, 1000, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_deposit_success() {
    let (mut ts, global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    ts.next_tx(ALICE);
    {
        // Deposit ETH
        let eth_amount = 1000000000;
        let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());

        deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

        assert_eq(deusd_minting::get_balance<ETH>(&management), eth_amount);

        // Deposit USDC
        let usdc_amount = 2000000;
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, ts.ctx());

        deusd_minting::deposit<USDC>(&mut management, &global_config, usdc_coin, ts.ctx());

        assert_eq(deusd_minting::get_balance<USDC>(&management), usdc_amount);
    };

    ts.next_tx(ADMIN);
    {
        // Deposit ETH
        let eth_amount = 2000000000;
        let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());

        deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

        assert_eq(deusd_minting::get_balance<ETH>(&management), 3000000000);
    };

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAmount)]
fun test_deposit_fail_if_amount_is_zero() {
    let (mut ts, global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    ts.next_tx(ALICE);
    {
        // Try to deposit zero amount - should fail
        let eth_coin = coin::mint_for_testing<ETH>(0, ts.ctx());
        deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());
    };

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_withdraw_success() {
    let (mut ts, global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    let eth_amount = 1000000000;
    let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());
    deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

    ts.next_tx(ADMIN);
    {
        // Withdraw ETH
        deusd_minting::withdraw<ETH>(&admin_cap, &mut management, &global_config, 400000000, ALICE, ts.ctx());
        assert_eq(deusd_minting::get_balance<ETH>(&management), 600000000); // Remaining balance after withdrawal

        ts.next_tx(ADMIN);
        let withdrawn_coin = ts.take_from_address<Coin<ETH>>(ALICE);
        assert_eq(withdrawn_coin.value(), 400000000);
        withdrawn_coin.burn_for_testing();
    };

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAmount)]
fun test_withdraw_fail_if_amount_is_zero() {
    let (mut ts, global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    let eth_amount = 1000000000;
    let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());
    deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

    ts.next_tx(ADMIN);
    {
        // Try to withdraw zero amount - should fail
        deusd_minting::withdraw<ETH>(&admin_cap, &mut management, &global_config, 0, ALICE, ts.ctx());
    };

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAddress)]
fun test_withdraw_fail_if_recipient_is_zero_address() {
    let (mut ts, global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    let eth_amount = 1000000000;
    let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());
    deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

    ts.next_tx(ADMIN);
    {
        // Try to withdraw to zero address - should fail
        deusd_minting::withdraw<ETH>(&admin_cap, &mut management, &global_config, 500000000, @0x0, ts.ctx());
    };

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotEnoughAmount)]
fun test_withdraw_fail_if_insufficient_balance() {
    let (mut ts, global_config, admin_cap, deusd_config, locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN1],
        1000000,
        500000,
    );

    let eth_amount = 1000000000;
    let eth_coin = coin::mint_for_testing<ETH>(eth_amount, ts.ctx());
    deusd_minting::deposit<ETH>(&mut management, &global_config, eth_coin, ts.ctx());

    ts.next_tx(ADMIN);
    {
        // Try to withdraw more than available balance - should fail
        deusd_minting::withdraw<ETH>(&admin_cap, &mut management, &global_config, 2000000000, ALICE, ts.ctx());
    };

    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

// === Helper Functions ===

public fun setup_test(): (Scenario, GlobalConfig, AdminCap, DeUSDConfig, LockedFundsManagement, DeUSDMintingManagement) {
    let mut ts = test_scenario::begin(ADMIN);

    let (global_config, admin_cap) = test_utils::setup_global_config(&mut ts, ADMIN);
    let deusd_config = test_utils::setup_deusd(&mut ts, ADMIN);
    let locked_funds_management = test_utils::setup_locked_funds(&mut ts, ADMIN);
    let deusd_minting_management = test_utils::setup_deusd_minting(&mut ts, ADMIN);

    (ts, global_config, admin_cap, deusd_config, locked_funds_management, deusd_minting_management)
}

public fun clean_test(
    ts: Scenario,
    global_config: GlobalConfig,
    admin_cap: AdminCap,
    deusd_config: DeUSDConfig,
    locked_funds_management: LockedFundsManagement,
    management: DeUSDMintingManagement,
) {
    test_scenario::return_shared(global_config);
    admin_cap::destroy_for_test(admin_cap);
    test_scenario::return_shared(deusd_config);
    test_scenario::return_shared(locked_funds_management);
    test_scenario::return_shared(management);
    ts.end();
}