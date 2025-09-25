module elixir::deusd;

use sui::coin::{Self, TreasuryCap, DenyCapV2, Coin};
use sui::event;
use sui::linked_table::{Self, LinkedTable};
use elixir::admin_cap::AdminCap;
use elixir::config::GlobalConfig;

// === Error codes ===

/// The address is zero.
const EZeroAddress: u64 = 1;
/// The amount is zero.
const EZeroAmount: u64 = 2;
/// Not deUSD treasury cap ID.
const ENotDeUSDTreasuryCapID: u64 = 3;
/// The deUSD treasury cap is not active.
const EDeUSDTreasuryCapNotActive: u64 = 4;

// === Constants ===

const DECIMALS: u8 = 6;

// === Structs ===

public struct DEUSD has drop {}

/// The capability to mint and burn deUSD tokens.
public struct DeUSDTreasuryCap has key, store {
    id: UID,
}

public struct DeUSDConfig has key {
    id: UID,
    treasury_cap: TreasuryCap<DEUSD>,
    deny_cap: DenyCapV2<DEUSD>,
    is_active_deusd_treasury_cap: LinkedTable<ID, bool>,
}

public struct DeUSDTreasuryCapView has copy, drop, store {
    id: ID,
    is_active: bool,
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

public struct DeUSDTreasuryCapCreated has copy, drop {
    to: address,
}

public struct DeUSDTreasuryCapStatusChanged has copy, drop {
    cap_id: ID,
    is_active: bool,
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
        is_active_deusd_treasury_cap: linked_table::new(ctx),
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

/// Create a new mint/burn capability and transfer it to the specified address.
/// Only callable by an admin.
public fun create_treasury_cap(
    _: &AdminCap,
    deusd_config: &mut DeUSDConfig,
    global_config: &GlobalConfig,
    to: address,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert!(to != @0x0, EZeroAddress);

    let cap = DeUSDTreasuryCap { id: object::new(ctx) };
    deusd_config.is_active_deusd_treasury_cap.push_back(object::id(&cap), true);

    transfer::transfer(cap, to);

    event::emit(DeUSDTreasuryCapCreated { to });
}

/// Set the active status of a deUSD treasury cap.
/// Only callable by an admin.
public fun set_treasury_cap_status(
    _: &AdminCap,
    deusd_config: &mut DeUSDConfig,
    global_config: &GlobalConfig,
    deusd_treasury_cap_id: ID,
    is_active: bool,
) {
    global_config.check_package_version();

    assert!(deusd_config.is_active_deusd_treasury_cap.contains(deusd_treasury_cap_id), ENotDeUSDTreasuryCapID);

    let old_is_active = deusd_config.is_active_deusd_treasury_cap.borrow_mut(deusd_treasury_cap_id);
    if (*old_is_active != is_active) {
        *old_is_active = is_active;

        event::emit(DeUSDTreasuryCapStatusChanged {
            cap_id: deusd_treasury_cap_id,
            is_active,
        });
    }
}

/// Mint new tokens to the specified account using the provided deUSD treasury cap.
public fun mint_with_cap(
    treasury_cap: &DeUSDTreasuryCap,
    deusd_config: &mut DeUSDConfig,
    global_config: &GlobalConfig,
    to: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();

    assert_is_active_deusd_treasury_cap(deusd_config, treasury_cap);
    assert!(to != @0x0, EZeroAddress);
    assert!(amount > 0, EZeroAmount);

    event::emit(Mint { to, amount });

    transfer::public_transfer(coin::mint(&mut deusd_config.treasury_cap, amount, ctx), to);
}

/// Burn tokens using the provided deUSD treasury cap.
public fun burn_with_cap(
    treasury_cap: &DeUSDTreasuryCap,
    deusd_config: &mut DeUSDConfig,
    global_config: &GlobalConfig,
    coin: Coin<DEUSD>,
    from: address,
) {
    global_config.check_package_version();
    assert_is_active_deusd_treasury_cap(deusd_config, treasury_cap);

    event::emit(Burn {
        from,
        amount: coin.value(),
    });

    coin::burn(&mut deusd_config.treasury_cap, coin);
}

// === Views ===

public fun total_supply(config: &DeUSDConfig): u64 {
    config.treasury_cap.total_supply()
}

public fun decimals(): u8 {
    DECIMALS
}

/// Get all deUSD treasury caps with their active status.
public fun get_treasury_caps(config: &DeUSDConfig): vector<DeUSDTreasuryCapView> {
    let mut caps = vector::empty<DeUSDTreasuryCapView>();
    let mut cap_id_opt = config.is_active_deusd_treasury_cap.front();
    while (cap_id_opt.is_some()) {
        let cap_id = *cap_id_opt.borrow();
        caps.push_back(DeUSDTreasuryCapView {
            id: cap_id,
            is_active: *config.is_active_deusd_treasury_cap.borrow(cap_id),
        });
        cap_id_opt = config.is_active_deusd_treasury_cap.next(cap_id);
    };
    caps
}

public fun is_active_deusd_treasury_cap(
    config: &DeUSDConfig,
    cap_id: ID,
): bool {
    *config.is_active_deusd_treasury_cap.borrow(cap_id)
}

// === Internal Functions ===

fun assert_is_active_deusd_treasury_cap(
    config: &DeUSDConfig,
    treasury_cap: &DeUSDTreasuryCap,
) {
    let cap_id = object::id(treasury_cap);

    assert!(
        *config.is_active_deusd_treasury_cap.borrow(cap_id),
        EDeUSDTreasuryCapNotActive
    );
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

#[test_only]
public fun extract_treasury_cap_view_for_test(
    treasury_cap_view: DeUSDTreasuryCapView,
): (ID, bool) {
    (treasury_cap_view.id, treasury_cap_view.is_active)
}

