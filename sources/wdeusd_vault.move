/// This module allows users to bridge deUSD from Ethereum to Sui via the SUI bridge.
/// The bridged deUSD is represented as wdeUSD (wrapped deUSD) on Sui.
/// Users can claim deUSD by depositing wdeUSD into the vault and can return deUSD
/// to get back their wdeUSD from the vault.
module elixir::wdeusd_vault;

// === Imports ===

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;
use elixir::admin_cap::AdminCap;
use elixir::deusd::{Self, DEUSD, DeUSDConfig};

// === Error codes ===

const EVaultPaused: u64 = 1;
const EVaultNotPaused: u64 = 2;
const EInvalidAmount: u64 = 3;
const EInsufficientFunds: u64 = 4;

// === Structs ===

public struct WDEUSDVault<phantom WDEUSD> has key, store {
    id: UID,
    balance: Balance<WDEUSD>,
    is_paused: bool,
}

// === Events ===

public struct VaultInitialized has copy, drop {
    vault_id: ID,
}

public struct VaultPaused has copy, drop {
    vault_id: ID,
}

public struct VaultUnpaused has copy, drop {
    vault_id: ID,
}

public struct DeUSDClaimed has copy, drop {
    vault_id: ID,
    sender: address,
    to: address,
    amount: u64,
}

public struct DeUSDReturned has copy, drop {
    vault_id: ID,
    sender: address,
    amount: u64,
    to: address,
}

// === Function ===

public fun initialize<W>(
    _: &AdminCap,
    ctx: &mut TxContext,
) {
    let vault = WDEUSDVault<W> {
        id: object::new(ctx),
        balance: balance::zero(),
        is_paused: false,
    };
    let vault_id = object::id(&vault);
    transfer::share_object(vault);

    event::emit(VaultInitialized {
        vault_id
    });
}

public fun pause<W>(_: &AdminCap, vault: &mut WDEUSDVault<W>) {
    vault.assert_not_paused();

    vault.is_paused = true;

    event::emit(VaultPaused {
        vault_id: object::id(vault)
    });
}

public fun unpause<W>(_: &AdminCap, vault: &mut WDEUSDVault<W>) {
    vault.assert_paused();

    vault.is_paused = false;

    event::emit(VaultUnpaused {
        vault_id: object::id(vault)
    });
}

public fun claim_deusd<W>(
    vault: &mut WDEUSDVault<W>,
    deusd_config: &mut DeUSDConfig,
    wdeusd_coin: Coin<W>,
    to: address,
    ctx: &mut TxContext,
) {
    vault.assert_not_paused();

    let amount = wdeusd_coin.value();
    assert!(amount > 0, EInvalidAmount);

    vault.balance.join(coin::into_balance(wdeusd_coin));

    deusd::mint(deusd_config, to, amount, ctx);

    event::emit(DeUSDClaimed {
        vault_id: object::id(vault),
        sender: ctx.sender(),
        to,
        amount,
    });
}

public fun return_deusd<W>(
    vault: &mut WDEUSDVault<W>,
    deusd_config: &mut DeUSDConfig,
    deusd_coin: Coin<DEUSD>,
    to: address,
    ctx: &mut TxContext,
) {
    vault.assert_not_paused();

    let amount = deusd_coin.value();
    assert!(amount > 0, EInvalidAmount);
    assert!(vault.balance.value() >= amount, EInsufficientFunds);

    deusd::burn_from(deusd_config, deusd_coin, ctx.sender());

    transfer::public_transfer(coin::from_balance(vault.balance.split(amount), ctx), to);

    event::emit(DeUSDReturned {
        vault_id: object::id(vault),
        sender: ctx.sender(),
        amount,
        to,
    });
}

// === Public views ===

public fun is_paused<W>(vault: &WDEUSDVault<W>): bool {
    vault.is_paused
}

public fun balance<W>(vault: &WDEUSDVault<W>): u64 {
    vault.balance.value()
}

// === Helpers ===

fun assert_not_paused<W>(vault: &WDEUSDVault<W>) {
    assert!(!vault.is_paused, EVaultPaused);
}

fun assert_paused<W>(vault: &WDEUSDVault<W>) {
    assert!(vault.is_paused, EVaultNotPaused);
}
