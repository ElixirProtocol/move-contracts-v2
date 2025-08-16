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

        // Prepare mint parameters
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";

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

        // Prepare mint parameters
        let nonce = 2;
        let expiry = 1000000001;
        let collateral_amount = 2000000001;
        let benefactor = @0xa9e41843ffead2ce82891fa46f0349f22023ed81a488ecefd5f570080368f81a;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, @elixir];
        let route_ratios = vector[6000, 4000]; // 60% to CUSTODIAN1, 40% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"4624cf9cb2ef3d2757d01b5d0f3cc6a2c6ad0bd8f529842b9c2fc595b91d7b7dc9faea2dd082ae64fe34ccf4a16e6309b52bb85773b6a40f9f0b947ab295820a";

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

        // Prepare mint parameters
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
        let signature = x"e47ff7849944bad59140ae20d2b304569c0cc47386b35d22ed1a54f89fdcb066917572ff87b55db8d060ac7bea7856788ebb82ecafc6240f8735e8a3b6e97903";

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

        // Prepare mint parameters
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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

        // Prepare mint parameters
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = @0x0; // Invalid beneficiary address
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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

        // Prepare mint parameters
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 0;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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

        // Prepare mint parameters
        let nonce = 1;
        let expiry = 1000000001;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 0;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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

        // Prepare mint parameters
        let nonce = 1;
        let expiry = 1000000000 - 1;
        let collateral_amount = 1000000000;
        let benefactor = BENEFACTOR;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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

        // Prepare mint parameters
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
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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

        // Prepare mint parameters
        let nonce = 1;
        let expiry = 1000000000;
        let collateral_amount = 1000000000;
        let benefactor = ALICE;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"b15026dcbe092a7b2f0010377d24bdaad56163120d5f27b42280d24d32dac32604727775376cf0db7fe8e7f6adc81ce858399ec6667cf7403690eed9252da308";
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
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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
#[expected_failure(abort_code = deusd_minting::EMaxMintPerBlockExceeded)]
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
        let signature = x"1b7fa88eae7163c325298fb5fdf9ef803646d1871e6bc25dc7d1cc2dbc6a0b28aba64acf20700c58063a0ce8a72c98595f893812f2c00203b7bab39513a12308";
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
        let signature = x"390e3ee9a417ea6f1ac0b8c61f8298f5430f97ee9bf4756e15a6ddd9fb062c19434fd631bbad05a3be97902365032f6cc015daccd658e7d2ad3626f5bec6a101";
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
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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
        let signature = x"e9436399320d06cdaf418752a067e0d17e5df4e6c88ecb4c35834bca7f2f911da7a5bb2014720b7ad91d524bdd63ad4a5d27dc32f186c998d79e9a3ce1537802";
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
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";
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
        let signature = x"6c043145ff06b8413a90669843caffead9ab91f26adc43078520436674e46eb152ef8baad303a783d808844ec7b712ba8b8b1cae98f7f16a15b9d7d93ba2040b";

        let deusd_supply_before = deusd::supply(&mut deusd_config);

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

        let deusd_supply_after = deusd::supply(&mut deusd_config);
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
        let signature = x"6a947d00ea29e172327766e53f4377f02bad7e364fc002e28bd61fd59dc2a6092a67eb2d71f0dae06ecc1e7aec564e4837095468d69f37ba1ae4ce702edf720b";

        let deusd_supply_before = deusd::supply(&mut deusd_config);

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

        let deusd_supply_after = deusd::supply(&mut deusd_config);
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
        let signature = x"6c043145ff06b8413a90669843caffead9ab91f26adc43078520436674e46eb152ef8baad303a783d808844ec7b712ba8b8b1cae98f7f16a15b9d7d93ba2040b";

        let deusd_supply_before = deusd::supply(&mut deusd_config);

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

        let deusd_supply_after = deusd::supply(&mut deusd_config);
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
#[expected_failure(abort_code = deusd_minting::EMaxRedeemPerBlockExceeded)]
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
        let signature = x"6c043145ff06b8413a90669843caffead9ab91f26adc43078520436674e46eb152ef8baad303a783d808844ec7b712ba8b8b1cae98f7f16a15b9d7d93ba2040b";

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
        let signature = x"45a55526ca22203bc6213e44c5c30474b92c5bbc15c38b945ebd2bd9c50d7e726150378333dad7240b06794e351dd30955715751a1ae863cfebf65ee90aede03";

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
        let signature = x"1ef757d9b2e450516cd59bd25a597d280d5083ae69fd3e661172bd2858dec7325678270b579aeb16b4166cc6646d473de88f49ee78075a584406a09b66e6e007";

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
        let signature = x"835afd172a4d9ab9b3a4cab17cddc82e6037c6f6409669f75509ef8587136bb6089bd141fced750028cd82522d1036330023cdd443752d55a03cf05ff483ec05";

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
        let signature = x"6c043145ff06b8413a90669843caffead9ab91f26adc43078520436674e46eb152ef8baad303a783d808844ec7b712ba8b8b1cae98f7f16a15b9d7d93ba2040b";

        let deusd_supply_before = deusd::supply(&mut deusd_config);

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

        let deusd_supply_after = deusd::supply(&mut deusd_config);
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
        let signature = x"6c043145ff06b8413a90669843caffead9ab91f26adc43078520436674e46eb152ef8baad303a783d808844ec7b712ba8b8b1cae98f7f16a15b9d7d93ba2040b";

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
        let signature = x"6c043145ff06b8413a90669843caffead9ab91f26adc43078520436674e46eb152ef8baad303a783d808844ec7b712ba8b8b1cae98f7f16a15b9d7d93ba2040b";

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
        let signature = x"6c043145ff06b8413a90669843caffead9ab91f26adc43078520436674e46eb152ef8baad303a783d808844ec7b712ba8b8b1cae98f7f16a15b9d7d93ba2040b";

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
        let signature = x"6c043145ff06b8413a90669843caffead9ab91f26adc43078520436674e46eb152ef8baad303a783d808844ec7b712ba8b8b1cae98f7f16a15b9d7d93ba2040b";

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
        let signature = x"9ed7a95cf71c2d2b5349adc6a6cf26bf10fc81dd568011457726f8427b34ed503b2bcd543847f5a8881f3b8402b527f10dffd787e309aa5ddd2278e7cb1e7600";

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
