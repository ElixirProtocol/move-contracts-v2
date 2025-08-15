#[test_only]
module elixir::deusd_minting_mint_and_redeem_tests;

use elixir::deusd::DEUSD;
use sui::coin::{Self, Coin};
use sui::clock;
use sui::test_utils::assert_eq;
use elixir::deusd_minting_tests::{setup_test, clean_test, ETH};
use elixir::deusd_minting::{Self};
use elixir::config::{Self};
use elixir::roles;

// Test constants
const MINTER1: address = @0xBB1;
const MINTER2: address = @0xBB2;
const CUSTODIAN1: address = @0xC1;
const CUSTODIAN2: address = @0xC2;
const ALICE: address = @0xa11ce;

#[test]
fun test_mint_success() {
    let (mut ts, mut global_config, admin_cap, mut deusd_config, mut management) = setup_test();

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

    ts.next_tx(MINTER1);
    {
        clock.set_for_testing(1000000000 * 1000);

        // Prepare mint parameters
        let collateral = coin::mint_for_testing<ETH>(1000000000, ts.ctx());
        let expiry = 1000000001;
        let nonce = 1;
        let benefactor = @0xa9e41843ffead2ce82891fa46f0349f22023ed81a488ecefd5f570080368f81a;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, CUSTODIAN2, @elixir];
        let route_ratios = vector[5000, 3000, 2000]; // 50% to CUSTODIAN1, 30% to CUSTODIAN2, 20% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"2c81dade6e96768d6e54ffe0733af0e8ebe1a4c1e1482ae8e557217b3b186fafdb76c383f9b8e6872604d35810f2edd8e2ac942c9369856ece44a77a9a96d404";

        deusd_minting::mint<ETH>(
            &mut management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral,
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

    ts.next_tx(MINTER2);
    {
        clock.set_for_testing(1000000000 * 1000);

        // Prepare mint parameters
        let collateral = coin::mint_for_testing<ETH>(1000000000, ts.ctx());
        let expiry = 1000000001;
        let nonce = 2;
        let benefactor = @0xa9e41843ffead2ce82891fa46f0349f22023ed81a488ecefd5f570080368f81a;
        let beneficiary = ALICE;
        let deusd_amount = 500000000;
        let route_addresses = vector[CUSTODIAN1, @elixir];
        let route_ratios = vector[6000, 4000]; // 60% to CUSTODIAN1, 40% to contract itself

        let public_key = x"15fffd5a17a3f7274979a1bba33d11d53c1d465667516d80dc6fe2b8fe4eaf01";
        let signature = x"15ed2b3aae0d1cc4745fd97dc5a1138f585b61ad70973f54accac196f0b623593f4521fdf8a6e911a0b6f56e7bd3fa2cdadc0fa128490a15517df37665b3920a";

        deusd_minting::mint<ETH>(
            &mut management,
            &mut deusd_config,
            &global_config,
            expiry,
            nonce,
            benefactor,
            beneficiary,
            collateral,
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
        assert_eq(custodian1_eth_coin.value(), 600000000);
        custodian1_eth_coin.burn_for_testing();

        let contract_eth_amount = deusd_minting::get_balance<ETH>(&management);
        assert_eq(contract_eth_amount, 600000000); // 200000000 from previous mint + 400000000 from this mint
    };

    sui::clock::destroy_for_testing(clock);
    clean_test(ts, global_config, admin_cap, deusd_config, management);
}

