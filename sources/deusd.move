module elixir::deusd;

use sui::coin::{Self, TreasuryCap, DenyCapV2, Coin};
use sui::event;

// === Error codes ===

/// The address is zero.
const EZeroAddress: u64 = 1;
/// The amount is zero.
const EZeroAmount: u64 = 2;

// === Constants ===

const DECIMALS: u8 = 6;

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
        DECIMALS,
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

// === Functions ===

/// Mint new tokens to the specified account.
public(package) fun mint(
    config: &mut DeUSDConfig,
    to: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(to != @0x0, EZeroAddress);
    assert!(amount > 0, EZeroAmount);

    event::emit(Mint { to, amount });

    transfer::public_transfer(coin::mint(&mut config.treasury_cap, amount, ctx), to);
}

public(package) fun burn_from(
    config: &mut DeUSDConfig,
    coin: Coin<DEUSD>,
    from: address,
) {
    event::emit(Burn {
        from,
        amount: coin.value(),
    });

    coin::burn(&mut config.treasury_cap, coin);
}

public fun total_supply(config: &DeUSDConfig): u64 {
    config.treasury_cap.total_supply()
}

// === Views ===

public fun decimals(): u8 {
    DECIMALS
}

// === Tests ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(DEUSD {}, ctx);
}

#[test_only]
public fun mint_for_test(
    config: &mut DeUSDConfig,
    amount: u64,
    ctx: &mut TxContext,
): Coin<DEUSD> {
    coin::mint(&mut config.treasury_cap, amount, ctx)
}