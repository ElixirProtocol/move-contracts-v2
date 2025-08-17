#[test_only]
module elixir::deusd_minting_mint_and_redeem_tests;

use elixir::deusd;
use sui::coin::{Self, Coin};
use sui::clock;
use sui::test_utils::assert_eq;
use elixir::locked_funds;
use elixir::deusd::DEUSD;
use elixir::deusd_minting_tests::{setup_test, clean_test, ETH, USDC};
use elixir::deusd_minting::{Self, get_minted_per_second};
use elixir::config::{Self};
use elixir::roles;

// === Constants ===

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";

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
        let route_addresses = vector[CUSTODIAN1, @elixir];
        let route_ratios = vector[6000, 4000]; // 60% to CUSTODIAN1, 40% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"d7d426e6c8004ced4c70273407521437ebf73a9b611830f524b95d3b2d745b606b59c892356b23b12bf6fbd0d58ed57ed89817542833bcc710e88436ab233006";

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
        let route_addresses = vector[@elixir, CUSTODIAN1];
        let route_ratios = vector[4000, 6000]; // 40% to contract itself, 60% to CUSTODIAN1

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"7ea93798d6cc4c4c2c697504772e9f4a3d80cccad491e6cdfa5159d31bca050a0a367625f799c1d8dbb3941368a1b4a302aa88e3341aee43ed071947d50bcd00";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        // This signature is for nonce 1, not nonce 2
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"1e261f8769f3629035ee69a0f78bc71a071b61ef8a6887972728e99e87a3af974575dce23be8faac3943b1bf1795f885f2d8f6e5a209b1bf76592d8dde225004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"2540b4dc9933d6d5575321eee738069001c286725b79cda68a9910028ac0c4475508fc3e0891a913b701c0f5b7ce6619afa58113c57f427982fb1d5264f2160f";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"03fae63dce410dde170fe83ab9f8acdbc4f757795756e1112b5df116d4bc7570297111113e25a36665b0933f060f472681fc19b29604887ccbc6577e53012a0f";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        let signature = x"712d6d8912356839a965b1200457b0786f3ae8df89efbd2e03d27d1535cfe59c3492963a2f851e6b3bd8c717533da2a14a6274bbcddffc229b32fb314d13a904";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"0a2704523b3166b794fb7b54ab2226d94d5bf3fa6ffda4b695c4d5ef39d141659e5e6c97030451a6ddfe75832f3d48539654feede0305a9a49314b7aa44e1004";
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"05167197354f455f22cd275ad4f1bfee65bb9fb650512bc6fabe8e3954ba358a22d34013ac5f02acee2b465c02949dacbcd9c0be1929916b972b1cc0b831970b";

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
        let signature = x"d58e7bf8b4a69b666c3d233862d62eb2dfa77f3e6e70756eecec0196909757e3485819563f32b1c793d48d3d297f4e30861a10f6ca8084319aac089174765b02";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"05167197354f455f22cd275ad4f1bfee65bb9fb650512bc6fabe8e3954ba358a22d34013ac5f02acee2b465c02949dacbcd9c0be1929916b972b1cc0b831970b";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"05167197354f455f22cd275ad4f1bfee65bb9fb650512bc6fabe8e3954ba358a22d34013ac5f02acee2b465c02949dacbcd9c0be1929916b972b1cc0b831970b";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"88181e1b2cf5536c1c0bd4d8e069decee5ebca6265dd2cf5377c60bccc43afc696f4b1c02d4440b2da85b156951325484146dc18e3224d52e3df5121567a5b04";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"9c5eaeae730d292752553b5c2b01d61bf37e18304691546bc3f70d508a4247238a52b2c9e4d1e1d4014688b2d6318f343e61e5494a102f994fdc25be58db5701";

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
        let signature = x"51556c9edcc31fd22890d29cc52279a2f63604a29f6166d8b4ee108c12754c8316fbe94362682a9dcdc920dd903dc15f1a25217c2c82266f392b4bebd21fa20f";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"05167197354f455f22cd275ad4f1bfee65bb9fb650512bc6fabe8e3954ba358a22d34013ac5f02acee2b465c02949dacbcd9c0be1929916b972b1cc0b831970b";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"05167197354f455f22cd275ad4f1bfee65bb9fb650512bc6fabe8e3954ba358a22d34013ac5f02acee2b465c02949dacbcd9c0be1929916b972b1cc0b831970b";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"05167197354f455f22cd275ad4f1bfee65bb9fb650512bc6fabe8e3954ba358a22d34013ac5f02acee2b465c02949dacbcd9c0be1929916b972b1cc0b831970b";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"05167197354f455f22cd275ad4f1bfee65bb9fb650512bc6fabe8e3954ba358a22d34013ac5f02acee2b465c02949dacbcd9c0be1929916b972b1cc0b831970b";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"05167197354f455f22cd275ad4f1bfee65bb9fb650512bc6fabe8e3954ba358a22d34013ac5f02acee2b465c02949dacbcd9c0be1929916b972b1cc0b831970b";

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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        vector[CUSTODIAN1, CUSTODIAN2, @elixir],
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
        let signature = x"a0032095c7505fa4c95b9376b9d43313547cee567f3b4fb8f15081f97154bc7cb2e6b4b36b86f59fb233c4298edca360ebc9f88877d3b3be6b9184fd61553404";

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
