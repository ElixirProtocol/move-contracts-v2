module test_coin::usdc;

use sui::coin;
use sui::coin::{DenyCapV2, TreasuryCap, Coin};
use sui::event;

// === Error codes ===

/// The address is zero.
const EZeroAddress: u64 = 1;
/// The amount is zero.
const EZeroAmount: u64 = 2;

// === Structs ===

public struct USDC has drop {}

public struct Management has key {
    id: UID,
    treasury_cap: TreasuryCap<USDC>,
    deny_cap: DenyCapV2<USDC>,
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

fun init(witness: USDC, ctx: &mut TxContext) {
    let (treasury_cap, deny_cap, metadata) = coin::create_regulated_currency_v2(
        witness,
        6,
        b"USDC.test",
        b"USDC Test Coin",
        b"USDC Test Coin",
        option::none(),
        true,
        ctx,
    );
    transfer::public_freeze_object(metadata);

    let management = Management {
        id: object::new(ctx),
        treasury_cap,
        deny_cap,
    };
    transfer::share_object(management);
}

// === Functions ===

public fun mint(
    config: &mut Management,
    to: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(to != @0x0, EZeroAddress);
    assert!(amount > 0, EZeroAmount);

    event::emit(Mint { to, amount });

    transfer::public_transfer(coin::mint(&mut config.treasury_cap, amount, ctx), to);
}

public fun burn(
    config: &mut Management,
    coin: Coin<USDC>,
    ctx: &mut TxContext,
) {
    event::emit(Burn {
        from: ctx.sender(),
        amount: coin.value(),
    });

    coin::burn(&mut config.treasury_cap, coin);
}

public fun total_supply(config: &Management): u64 {
    config.treasury_cap.total_supply()
}
