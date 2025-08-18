#[test_only]
module elixir::deusd_minting_mint_and_redeem_tests;

use elixir::deusd;
use sui::coin::{Self, Coin};
use sui::clock;
use sui::test_utils::assert_eq;
use test_coin::test_coins::{ETH, USDC};
use elixir::locked_funds;
use elixir::deusd::DEUSD;
use elixir::deusd_minting_tests::{setup_test, clean_test};
use elixir::deusd_minting::{Self, get_minted_per_second};
use elixir::config;
use elixir::roles;

// === Constants ===

const PACKAGE_ADDRESS: address = @0xee;
const MINTER1: address = @0xBB1;
const MINTER2: address = @0xBB2;
const REDEEMER1: address = @0xBC1;
const REDEEMER2: address = @0xBC2;
const CUSTODIAN1: address = @0xC1;
const CUSTODIAN2: address = @0xC2;
const BENEFACTOR: address = @0xa9e41843ffead2ce82891fa46f0349f22023ed81a488ecefd5f570080368f81a;
const ALICE: address = @0xa11ce;

// === Mint tests ===

#[test]
fun test_mint_success() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());
    config::add_role(&admin_cap, &mut global_config, MINTER2, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(5000000002, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";

        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );

        ts.next_tx(beneficiary);

        // Check that the minting was successful
        let deusd_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq(deusd_coin.value(), deusd_amount);
        deusd_coin.burn_for_testing();

        // Check that collaterals were distributed correctly
        let custodian1_eth_coin = ts.take_from_address<Coin<ETH>>(CUSTODIAN1);
        assert_eq(custodian1_eth_coin.value(), 500000000);
        custodian1_eth_coin.burn_for_testing();

        let custodian2_eth_coin = ts.take_from_address<Coin<ETH>>(CUSTODIAN2);
        assert_eq(custodian2_eth_coin.value(), 300000000);
        custodian2_eth_coin.burn_for_testing();

        let contract_eth_amount = deusd_minting::get_balance<ETH>(&management);
        assert_eq(contract_eth_amount, 200000000);
    };

    // Mint up to the maximum allowed for the current second
    ts.next_tx(MINTER2);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 2;
        let expiry = 1000000001;
        let collateral_amount = 2000000001;
        let benefactor = @0xa9e41843ffead2ce82891fa46f0349f22023ed81a488ecefd5f570080368f81a;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, PACKAGE_ADDRESS];
        let route_ratios = vector[6000, 4000]; // 60% to CUSTODIAN1, 40% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"ef0484c8cf4ef4206be085522acf107f5ba517b9dbd31f0bc5534b0713b92253ab19ca339d8686f6fa15ebce2eb319c3d016e2a94f3ec17466bd6ebabae58600";

        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );

        ts.next_tx(beneficiary);

        // Check that the minting was successful
        let deusd_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq(deusd_coin.value(), deusd_amount);
        deusd_coin.burn_for_testing();

        // Check that collaterals were distributed correctly
        let custodian1_eth_coin = ts.take_from_address<Coin<ETH>>(CUSTODIAN1);
        assert_eq(custodian1_eth_coin.value(), 1200000000);
        custodian1_eth_coin.burn_for_testing();

        let contract_eth_amount = deusd_minting::get_balance<ETH>(&management);
        assert_eq(contract_eth_amount, 1000000001); // 200000000 from previous mint + 80000001 from this mint

        assert_eq(get_minted_per_second(&management, 1000000000), 1000000000);
    };

    // Mint again in the next second to test the mint limit
    ts.next_tx(MINTER2);
    {
        clock.set_for_testing(1000000001 * 1000);

        let nonce = 3;
        let expiry = 1000000001;
        // 1 unit remaining when calculating collateral distribution should be sent to the contract
        let collateral_amount = 2000000001;
        let benefactor = @0xa9e41843ffead2ce82891fa46f0349f22023ed81a488ecefd5f570080368f81a;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[PACKAGE_ADDRESS, CUSTODIAN1];
        let route_ratios = vector[4000, 6000]; // 40% to contract itself, 60% to CUSTODIAN1

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1a21f0772c8d7499642e5c7076f9f6fbafc41239d6720aa4679eb3f9cbebecd5995fb966878cb14269023092a18dfbad3239f83878a58dcb95e10a5e8a72da0d";

        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );

        ts.next_tx(beneficiary);

        // Check that the minting was successful
        let deusd_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq(deusd_coin.value(), deusd_amount);
        deusd_coin.burn_for_testing();

        // Check that collaterals were distributed correctly
        let custodian1_eth_coin = ts.take_from_address<Coin<ETH>>(CUSTODIAN1);
        assert_eq(custodian1_eth_coin.value(), 1200000001);
        custodian1_eth_coin.burn_for_testing();

        let contract_eth_amount = deusd_minting::get_balance<ETH>(&management);
        assert_eq(contract_eth_amount, 1800000001); // 1000000001 from previous mints + 80000000 from this mint

        assert_eq(get_minted_per_second(&management, 1000000001), 500000000);
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_mint_fail_if_not_minter() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER2); // MINTER2 is not a registered minter
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAddress)]
fun test_mint_fail_if_beneficiary_is_zero() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = @0x0; // Invalid beneficiary address
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAmount)]
fun test_mint_fail_if_collateral_amount_is_zero() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 0;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAmount)]
fun test_mint_fail_if_deusd_amount_is_zero() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 0;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ESignatureExpired)]
fun test_mint_fail_if_order_expired() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000000 - 1;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidSignature)]
fun test_mint_fail_if_invalid_signature() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 2;
        let expiry = 1000000000;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        // This signature is for nonce 1, not nonce 2
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidSigner)]
fun test_mint_fail_if_signer_not_benefactor() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000000;
        let collateral_amount = 1000000000;
        let benefactor = ALICE;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"d6d1b7a0da6672ecfc198e1bf19976d2a45d8509d4d261370e0027af1392a4a6d25b6aacf95d8318e1b28252499018a5a5e203d0c645f50e265fd7630c9dea02";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidRoute)]
fun test_mint_fail_if_route_addresses_and_ratios_length_mismatch() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        // Prepare mint parameters with mismatched route vectors
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2]; // 2 addresses
        let route_ratios = vector[5000, 3000, 2000]; // 3 ratios - mismatch!

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidRoute)]
fun test_mint_fail_if_empty_route() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        // Prepare mint parameters with empty route
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[]; // Empty route
        let route_ratios = vector[]; // Empty route

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidRoute)]
fun test_mint_fail_if_route_contains_non_custodian() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        // Prepare mint parameters with non-custodian address
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, ALICE]; // ALICE is not a custodian
        let route_ratios = vector[5000, 5000];

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EMaxMintPerSecondExceeded)]
fun test_mint_fail_if_max_mint_per_second_exceeded() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        500000000,
        1500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        // Prepare mint parameters that exceed max mint per second
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000001; // This exceeds the 500M limit
        let route_addresses = vector[CUSTODIAN1];
        let route_ratios = vector[10000];

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"a41b0d8bae9641ef8702e936abe4e9f91e138efe48651dda107b03879071ccb853d94bb5c2e157b4a3a255aaef94ff128e8f5a12a6fb9284cf0f0db5d4824f0b";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidNonce)]
fun test_mint_fail_if_nonce_is_zero() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        // Prepare mint parameters with zero nonce
        let nonce = 0; // Invalid nonce
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1];
        let route_ratios = vector[10000];

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"2888df227156a60ff5e7e401e8588484232b6ecbf381560c008338490615bd9121fff277d4b42567c61890a342a4e01cf76a1bafb21cec001ef8c718e987e00d";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidNonce)]
fun test_mint_fail_if_nonce_already_used() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());
    config::add_role(&admin_cap, &mut global_config, MINTER2, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(6000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    // First mint with nonce 1 - should succeed
    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1];
        let route_ratios = vector[10000];

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    // Second mint with same nonce 1 - should fail
    ts.next_tx(MINTER2);
    {
        clock.set_for_testing(1000000001 * 1000);

        let nonce = 1; // Same nonce as before - should fail
        let expiry = 1000000002;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1];
        let route_ratios = vector[10000];

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"30977a8f70898ac8ec4d69a736fc748249b6259e1265d1c5e272d524a8af1f502ffcfa1690ec494f4f11bdd7fe7aa5ca60d4bd1e3a521298eaa0961da0aa2108";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EUnsupportedAsset)]
fun test_mint_fail_if_asset_not_supported() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    // Note: We don't add ETH as a supported asset
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1];
        let route_ratios = vector[10000];

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
fun test_mint_single_custodian_route() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, MINTER1, roles::role_minter());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let eth_coin = coin::mint_for_testing<ETH>(3000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            eth_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        // Test with single custodian route (100% to one custodian)
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1]; // Single custodian
        let route_ratios = vector[10000]; // 100% to CUSTODIAN1

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1351734f44b966f72793064132c42e50c5c08bc0465456e069a4d75e99f431247bf41a7f8b5ddd92eda11451ccf491f2d2720153171f39e81bb30d64c76e320a";
        deusd_minting::mint<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            route_addresses,
            route_ratios,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );

        ts.next_tx(beneficiary);
        let deusd_coin = ts.take_from_sender<Coin<DEUSD>>();
        assert_eq(deusd_coin.value(), deusd_amount);
        deusd_coin.burn_for_testing();

        // Check that all collateral went to CUSTODIAN1
        let custodian1_eth_coin = ts.take_from_address<Coin<ETH>>(CUSTODIAN1);
        assert_eq(custodian1_eth_coin.value(), collateral_amount);
        custodian1_eth_coin.burn_for_testing();

        // Contract should have no balance
        let contract_eth_amount = deusd_minting::get_balance<ETH>(&management);
        assert_eq(contract_eth_amount, 0);
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

// === Redeem Tests ===


#[test]
fun test_redeem_success() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    deusd_minting::add_supported_asset<USDC>(&admin_cap, &mut management, &global_config);

    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());
    config::add_role(&admin_cap, &mut global_config, REDEEMER2, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());
    let usdc_coin = coin::mint_for_testing<USDC>(500000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, usdc_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"6e7ff46a9555f6e92b1931d3b12a0619b7aec8dcfcf553d6b92d752f217539e688e5164db3f2f43ea235ca29f04c0897282422a1c42eb11f1d69085b281fbb03";

        let deusd_supply_before = deusd::total_supply(&deusd_config);

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );

        let deusd_supply_after = deusd::total_supply(&deusd_config);
        assert_eq(deusd_supply_before - deusd_supply_after, deusd_amount);

        ts.next_tx(beneficiary);
        let beneficiary_eth_coin = ts.take_from_sender<Coin<ETH>>();
        assert_eq(beneficiary_eth_coin.value(), collateral_amount);
        beneficiary_eth_coin.burn_for_testing();

        let contract_eth_amount = deusd_minting::get_balance<ETH>(&management);
        assert_eq(contract_eth_amount, 9000000000);

        assert_eq(deusd_minting::get_redeemed_per_second(&management, 1000000000), 500000000);
    };

    ts.next_tx(REDEEMER2);
    {
        clock.set_for_testing(1000000001 * 1000);

        let nonce = 2;
        let expiry = 1000000001;
        let collateral_amount = 500000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 100000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"52643ac20a5b85630df6ba943d60f60924c8301e43002e2172820511b195e107631f404f2a055407e336f0308f1bf0abca1c9e5ddb3bd2fd7e98a679e5175b05";

        let deusd_supply_before = deusd::total_supply(&deusd_config);

        deusd_minting::redeem<USDC>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );

        let deusd_supply_after = deusd::total_supply(&deusd_config);
        assert_eq(deusd_supply_before - deusd_supply_after, deusd_amount);

        ts.next_tx(beneficiary);
        let beneficiary_usdc_coin = ts.take_from_sender<Coin<USDC>>();
        assert_eq(beneficiary_usdc_coin.value(), collateral_amount);
        beneficiary_usdc_coin.burn_for_testing();

        let contract_usdc_amount = deusd_minting::get_balance<USDC>(&management);
        assert_eq(contract_usdc_amount, 0);

        assert_eq(deusd_minting::get_redeemed_per_second(&management, 1000000001), 100000000);
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ENotAuthorized)]
fun test_redeem_fail_if_not_redeemer() {
    let (mut ts, global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"6e7ff46a9555f6e92b1931d3b12a0619b7aec8dcfcf553d6b92d752f217539e688e5164db3f2f43ea235ca29f04c0897282422a1c42eb11f1d69085b281fbb03";

        let deusd_supply_before = deusd::total_supply(&deusd_config);

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );

        let deusd_supply_after = deusd::total_supply(&deusd_config);
        assert_eq(deusd_supply_before - deusd_supply_after, deusd_amount);

        ts.next_tx(beneficiary);
        let beneficiary_eth_coin = ts.take_from_sender<Coin<ETH>>();
        assert_eq(beneficiary_eth_coin.value(), collateral_amount);
        beneficiary_eth_coin.burn_for_testing();

        let contract_eth_amount = deusd_minting::get_balance<ETH>(&management);
        assert_eq(contract_eth_amount, 9000000000);

        assert_eq(deusd_minting::get_redeemed_per_second(&management, 1000000000), 500000000);
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EMaxRedeemPerSecondExceeded)]
fun test_redeem_fail_if_max_redeem_per_second_exceeded() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        499999999,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000; // Exceeds max redeem per second (499999999)

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"6e7ff46a9555f6e92b1931d3b12a0619b7aec8dcfcf553d6b92d752f217539e688e5164db3f2f43ea235ca29f04c0897282422a1c42eb11f1d69085b281fbb03";

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidNonce)]
fun test_redeem_fail_if_nonce_is_zero() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 0;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"fb0fcb8303e3b977844bc9c22c72c4f2ebe4e83b42d767a572dcc626751d512d3683614a891fa24c8d9fa7ed04a397e90235ab193fde5f53392cc4a808d8de07";

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidNonce)]
fun test_redeem_fail_if_nonce_already_used() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    // First redeem with nonce 1
    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 100000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"eabec2615403f67adb81950ac5e4b63bd6e09d8c7e4272ba0372f62bb6efc046d0f68c66b811375f85f7340118959f54247efc5193c93f2542c0ebd148c96209";

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    // Try to redeem again with the same nonce (should fail)
    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000001 * 1000);

        let nonce = 1; // Same nonce as before
        let expiry = 1000000002;
        let collateral_amount = 500000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 50000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"a0af1ffa460492eebce8f6a6fdb4cfbba93924247d0fd5a2dce5df7481944f29e9dccfd79224171eecf955595571bae00b3a5e64495d3f519b860db99358770f";

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EUnsupportedAsset)]
fun test_redeem_fail_if_asset_not_supported() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"6e7ff46a9555f6e92b1931d3b12a0619b7aec8dcfcf553d6b92d752f217539e688e5164db3f2f43ea235ca29f04c0897282422a1c42eb11f1d69085b281fbb03";

        let deusd_supply_before = deusd::total_supply(&deusd_config);

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );

        let deusd_supply_after = deusd::total_supply(&deusd_config);
        assert_eq(deusd_supply_before - deusd_supply_after, deusd_amount);

        ts.next_tx(beneficiary);
        let beneficiary_eth_coin = ts.take_from_sender<Coin<ETH>>();
        assert_eq(beneficiary_eth_coin.value(), collateral_amount);
        beneficiary_eth_coin.burn_for_testing();

        let contract_eth_amount = deusd_minting::get_balance<ETH>(&management);
        assert_eq(contract_eth_amount, 9000000000);

        assert_eq(deusd_minting::get_redeemed_per_second(&management, 1000000000), 500000000);
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAddress)]
fun test_redeem_fail_if_beneficiary_is_zero_address() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = @0x0;
        let deusd_amount = 500000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"6e7ff46a9555f6e92b1931d3b12a0619b7aec8dcfcf553d6b92d752f217539e688e5164db3f2f43ea235ca29f04c0897282422a1c42eb11f1d69085b281fbb03";

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAmount)]
fun test_redeem_fail_if_collateral_amount_is_zero() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 0;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"6e7ff46a9555f6e92b1931d3b12a0619b7aec8dcfcf553d6b92d752f217539e688e5164db3f2f43ea235ca29f04c0897282422a1c42eb11f1d69085b281fbb03";

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidAmount)]
fun test_redeem_fail_if_deusd_amount_is_zero() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 0;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"6e7ff46a9555f6e92b1931d3b12a0619b7aec8dcfcf553d6b92d752f217539e688e5164db3f2f43ea235ca29f04c0897282422a1c42eb11f1d69085b281fbb03";

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::ESignatureExpired)]
fun test_redeem_fail_if_signature_expired() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000002 * 1000); // Set clock after expiry

        let nonce = 1;
        let expiry = 1000000001; // Expiry before current time
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"6e7ff46a9555f6e92b1931d3b12a0619b7aec8dcfcf553d6b92d752f217539e688e5164db3f2f43ea235ca29f04c0897282422a1c42eb11f1d69085b281fbb03";

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidSignature)]
fun test_redeem_fail_if_invalid_signature() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b"; // Invalid signature

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}

#[test]
#[expected_failure(abort_code = deusd_minting::EInvalidSigner)]
fun test_redeem_fail_if_signer_mismatch() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut locked_funds_management, mut management) = setup_test();

    deusd_minting::initialize(
        &admin_cap,
        &mut management,
        &global_config,
        PACKAGE_ADDRESS,
        vector[CUSTODIAN1, CUSTODIAN2, PACKAGE_ADDRESS],
        1000000000,
        500000000,
    );

    deusd_minting::add_supported_asset<ETH>(&admin_cap, &mut management, &global_config);
    config::add_role(&admin_cap, &mut global_config, REDEEMER1, roles::role_redeemer());

    // Deposit some collateral to contract for redeeming
    let eth_coin = coin::mint_for_testing<ETH>(10000000000, ts.ctx());
    deusd_minting::deposit(&mut management, &global_config, eth_coin, ts.ctx());

    let mut clock = clock::create_for_testing(ts.ctx());

    ts.next_tx(BENEFACTOR);
    {
        let deusd_coin = deusd::mint_for_test(&mut deusd_config, 5000000000, ts.ctx());
        locked_funds::deposit(
            &mut locked_funds_management,
            &global_config,
            deusd_coin,
            ts.ctx(),
        );
    };

    ts.next_tx(REDEEMER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = ALICE;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"7fd3a7eb15afd88593dc6d38cd12b35d765e9b030c86adf01f486fedfcce2e1a6ebfe0f159e367967d6f4c587e62ffaf1cfff741566848acedf71399aec7f506";

        deusd_minting::redeem<ETH>(
            &mut management,
            &mut locked_funds_management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral_amount,
            deusd_amount,
            public_key,
            signature,
            &clock,
            ts.ctx(),
        );
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, locked_funds_management, management);
}
