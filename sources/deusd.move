module elixir::deusd;

use elixir::config::GlobalConfig;
use sui::coin::{Self, TreasuryCap, DenyCapV2, Coin};
use sui::event;

// === Error codes ===

/// The address is zero.
const EZeroAddress: u64 = 1;
/// The amount is zero.
const EZeroAmount: u64 = 2;

// === Structs ===

public struct DEUSD has drop {}

public struct DeUSDConfig has key {
    id: UID,
    treasury_cap: TreasuryCap<DEUSD>,
    deny_cap: DenyCapV2<DEUSD>,
}

// === Events ===

public struct Mint has copy, drop, store {
    to: address,
    amount: u64,
}

public struct Burn has copy, drop, store {
    from: address,
    amount: u64,
}

// === Initialization ===

fun init(witness: DEUSD, ctx: &mut TxContext) {
    let (treasury_cap, deny_cap, metadata) = coin::create_regulated_currency_v2(
        witness,
        6,
        b"deUSD",
        b"Elixir's deUSD",
        b"Elixir's deUSD",
        option::none(),
        true,
        ctx,
    );
    transfer::public_freeze_object(metadata);

    let management = DeUSDConfig {
        id: object::new(ctx),
        treasury_cap,
        deny_cap,
    };
    transfer::share_object(management);
}

// === Public Functions ===

/// Mint new tokens to the specified account. This checks that the caller is a minter.
public(package) fun mint(
    config: &mut DeUSDConfig,
    to: address,
    amount: u64,
    global_config: &GlobalConfig,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();

    assert!(to != @0x0, EZeroAddress);
    assert!(amount > 0, EZeroAmount);

    event::emit(Mint { to, amount });

    transfer::public_transfer(coin::mint(&mut config.treasury_cap, amount, ctx), to);
}

public fun burn(
    config: &mut DeUSDConfig,
    coin: Coin<DEUSD>,
    global_config: &GlobalConfig,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();

    event::emit(Burn {
        from: ctx.sender(),
        amount: coin.value(),
    });

    coin::burn(&mut config.treasury_cap, coin);
}

// === Tests ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(DEUSD {}, ctx);
}

#[test_only]
public fun mint_for_test(
    config: &mut DeUSDConfig,
    to: address,
    amount: u64,
    ctx: &mut TxContext,
): Coin<DEUSD> {
    assert!(to != @0x0, EZeroAddress);
    assert!(amount > 0, EZeroAmount);

    coin::mint(&mut config.treasury_cap, amount, ctx)
}