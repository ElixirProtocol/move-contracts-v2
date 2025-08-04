module elixir::deusd;

use sui::coin::{Self, TreasuryCap, DenyCapV2, Coin};
use sui::event;

// === Error codes ===

/// The `sender` is not the admin.
const ENotAdmin: u64 = 1;
/// The `sender` is not the minter.
const ENotMinter: u64 = 2;
/// The address is zero.
const EZeroAddress: u64 = 3;
/// The amount is zero.
const EZeroAmount: u64 = 4;

// === Structs ===

public struct DEUSD has drop {}

public struct Management has key {
    id: UID,
    admin: address,
    minter: address,
    treasury_cap: TreasuryCap<DEUSD>,
    deny_cap: DenyCapV2<DEUSD>,
}

// === Events ===

public struct MinterUpdated has copy, drop, store {
    new_minter: address,
    old_minter: address,
}

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
        b"DEUSD",
        option::none(),
        true,
        ctx,
    );
    transfer::public_freeze_object(metadata);

    let management = Management {
        id: object::new(ctx),
        admin: @admin,
        minter: @admin,
        treasury_cap,
        deny_cap,
    };
    transfer::share_object(management);
}

// === Public Functions ===

/// Set a new minter. This checks that the caller is the administrator.
public fun set_minter(
    management: &mut Management,
    new_minter: address,
    ctx: &mut TxContext,
) {
    assert_is_admin(management, ctx);
    assert!(new_minter != @0x0, EZeroAddress);

    let old_minter = management.minter;

    management.minter = new_minter;

    event::emit(MinterUpdated { new_minter, old_minter })
}

/// Mint new tokens to the specified account. This checks that the caller is a minter.
public fun mint(management: &mut Management, to: address, amount: u64, ctx: &mut TxContext): Coin<DEUSD> {
    assert_is_minter(management, ctx);
    assert!(to != @0x0, EZeroAddress);
    assert!(amount > 0, EZeroAmount);

    event::emit(Mint { to, amount });

    coin::mint(&mut management.treasury_cap, amount, ctx)
}

public fun burn(
    management: &mut Management,
    coin: Coin<DEUSD>,
    ctx: &mut TxContext,
) {
    event::emit(Burn {
        from: ctx.sender(),
        amount: coin.value(),
    });

    coin::burn(&mut management.treasury_cap, coin);
}

// === Private Functions ===

fun assert_is_admin(management: &Management, ctx: &TxContext) {
    assert!(ctx.sender() == management.admin, ENotAdmin);
}

fun assert_is_minter(management: &Management, ctx: &TxContext) {
    assert!(ctx.sender() == management.minter, ENotMinter);
}

// === Tests ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(DEUSD {}, ctx);
}