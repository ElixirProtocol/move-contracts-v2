module elixir::deusd;

use elixir::admin_cap::{AdminCap};
use elixir::package_version::{Self, PackageVersion};
use sui::coin::{Self, TreasuryCap, DenyCapV2, Coin};
use sui::event;

// === Error codes ===

/// The `sender` is not the minter.
const ENotMinter: u64 = 1;
/// The address is zero.
const EZeroAddress: u64 = 2;
/// The amount is zero.
const EZeroAmount: u64 = 3;

// === Structs ===

public struct DEUSD has drop {}

public struct Config has key {
    id: UID,
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
        b"Elixir's deUSD",
        option::none(),
        true,
        ctx,
    );
    transfer::public_freeze_object(metadata);

    let management = Config {
        id: object::new(ctx),
        minter: @admin,
        treasury_cap,
        deny_cap,
    };
    transfer::share_object(management);
}

// === Public Functions ===

/// Set a new minter. This checks that the caller is the administrator.
public fun set_minter(
    _: &AdminCap,
    config: &mut Config,
    new_minter: address,
    package_version: &PackageVersion,
    _: &mut TxContext,
) {
    package_version::check_package_version(package_version);
    assert!(new_minter != @0x0, EZeroAddress);

    let old_minter = config.minter;

    config.minter = new_minter;

    event::emit(MinterUpdated { new_minter, old_minter });
}

/// Mint new tokens to the specified account. This checks that the caller is a minter.
public fun mint(
    config: &mut Config,
    to: address,
    amount: u64,
    version: &PackageVersion,
    ctx: &mut TxContext,
): Coin<DEUSD> {
    package_version::check_package_version(version);
    assert_is_minter(config, ctx);
    assert!(to != @0x0, EZeroAddress);
    assert!(amount > 0, EZeroAmount);

    event::emit(Mint { to, amount });

    coin::mint(&mut config.treasury_cap, amount, ctx)
}

public fun burn(
    config: &mut Config,
    coin: Coin<DEUSD>,
    version: &PackageVersion,
    ctx: &mut TxContext,
) {
    package_version::check_package_version(version);

    event::emit(Burn {
        from: ctx.sender(),
        amount: coin.value(),
    });

    coin::burn(&mut config.treasury_cap, coin);
}

// === Private Functions ===

fun assert_is_minter(management: &Config, ctx: &TxContext) {
    assert!(ctx.sender() == management.minter, ENotMinter);
}

// === Tests ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(DEUSD {}, ctx);
}