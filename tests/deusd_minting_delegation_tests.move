#[test_only]
module elixir::deusd_minting_delegation_tests;

use sui::test_utils::assert_eq;
use elixir::deusd_minting_tests::{setup_test, clean_test};
use elixir::deusd_minting::{Self};

// Test constants
const ADMIN: address = @0xad;
const MINTER: address = @0xBB;
const CUSTODIAN: address = @0xDD;
const ALICE: address = @0xa11ce;

const DELEGATED_SIGNER_STATUS_PENDING: u8 = 1;
const DELEGATED_SIGNER_STATUS_ACCEPTED: u8 = 2;
const DELEGATED_SIGNER_STATUS_REJECTED: u8 = 3;

#[test]
fun test_delegation_e2e() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN],
        1000000,
        500000,
    );

    // ADMIN sets delegated signer to MINTER
    deusd_minting::set_delegated_signer(&mut management, &global_config, MINTER, ts.ctx());
    assert_eq(
        deusd_minting::get_delegated_signer_status(&management, MINTER, ADMIN),
        DELEGATED_SIGNER_STATUS_PENDING,
    );

    // ADMIN sets delegated signer to ALICE
    deusd_minting::set_delegated_signer(&mut management, &global_config, ALICE, ts.ctx());
    assert_eq(
        deusd_minting::get_delegated_signer_status(&management, ALICE, ADMIN),
        DELEGATED_SIGNER_STATUS_PENDING,
    );

    ts.next_tx(MINTER);
    // MINTER confirms delegation from ADMIN
    deusd_minting::confirm_delegated_signer(&mut management, &global_config, ADMIN, ts.ctx());
    assert_eq(
        deusd_minting::get_delegated_signer_status(&management, MINTER, ADMIN),
        DELEGATED_SIGNER_STATUS_ACCEPTED,
    );

    // Test multiple delegators to same delegate
    ts.next_tx(ALICE);
    deusd_minting::set_delegated_signer(&mut management, &global_config, MINTER, ts.ctx());
    assert_eq(
        deusd_minting::get_delegated_signer_status(&management, MINTER, ALICE),
        DELEGATED_SIGNER_STATUS_PENDING,
    );

    ts.next_tx(MINTER);
    // MINTER confirms delegation from ALICE too
    deusd_minting::confirm_delegated_signer(&mut management, &global_config, ALICE, ts.ctx());
    assert_eq(
        deusd_minting::get_delegated_signer_status(&management, MINTER, ALICE),
        DELEGATED_SIGNER_STATUS_ACCEPTED,
    );

    ts.next_tx(ALICE);
    // ALICE removes delegated signer
    deusd_minting::remove_delegated_signer(&mut management, &global_config, MINTER, ts.ctx());
    assert_eq(
        deusd_minting::get_delegated_signer_status(&management, MINTER, ALICE),
        DELEGATED_SIGNER_STATUS_REJECTED,
    );

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_set_delegated_signer_not_initialized() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Try to set delegated signer without initialization - should fail
    deusd_minting::set_delegated_signer(&mut management, &global_config, MINTER, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotInitialized)]
fun test_confirm_delegated_signer_not_initialized() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    // Try to confirm delegated signer without initialization - should fail
    deusd_minting::confirm_delegated_signer(&mut management, &global_config, ADMIN, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EDelegationNotInitiated)]
fun test_confirm_delegated_signer_not_pending_delegation() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN],
        1000000,
        500000,
    );

    deusd_minting::set_delegated_signer_for_test(
        &mut management,
        ADMIN,
        MINTER,
        DELEGATED_SIGNER_STATUS_ACCEPTED,
        ts.ctx(),
    );

    ts.next_tx(ALICE);
    // Try to confirm delegated signer without initialization - should fail
    deusd_minting::confirm_delegated_signer(&mut management, &global_config, ADMIN, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EDelegationNotInitiated)]
fun test_remove_delegated_signer_if_no_delegator() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN],
        1000000,
        500000,
    );

    ts.next_tx(ADMIN);
    // Try to remove delegated signer without setting it first - should fail
    deusd_minting::remove_delegated_signer(&mut management, &global_config, MINTER, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EDelegationNotInitiated)]
fun test_remove_delegated_signer_wrong_delegator() {
    let (mut ts, global_config, admin_cap, deusd_config, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        vector[CUSTODIAN],
        1000000,
        500000,
    );

    // ADMIN sets delegated signer to MINTER
    deusd_minting::set_delegated_signer(&mut management, &global_config, MINTER, ts.ctx());


    ts.next_tx(ALICE); // ALICE did not delegate to MINTER
    // Try to remove delegated signer as wrong delegator - should fail
    deusd_minting::remove_delegated_signer(&mut management, &global_config, MINTER, ts.ctx());

    clean_test(ts, global_config, admin_cap, deusd_config, management);
}