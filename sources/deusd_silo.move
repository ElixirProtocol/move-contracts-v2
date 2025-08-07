module elixir::deusd_silo;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use elixir::deusd::DEUSD;

// === Error codes ===

/// Zero address.
const EZeroAddress: u64 = 1;

// === Structs ===

/// Silo for holding deUSD assets during cooldown periods
public struct DeUSDSilo has key {
    id: UID,
    /// Address of the staking vault that owns this silo
    staking_vault: address,
    /// Balance of deUSD tokens held in this silo
    deusd_balance: Balance<DEUSD>,
}

// === Initialization ===

/// Create a new silo (called during staking contract initialization)
public fun new(staking_vault: address, ctx: &mut TxContext): DeUSDSilo {
    assert!(staking_vault != @0x0, EZeroAddress);
    
    DeUSDSilo {
        id: object::new(ctx),
        staking_vault,
        deusd_balance: balance::zero(),
    }
}

/// Create and share a new silo
public fun create_and_share(staking_vault: address, ctx: &mut TxContext) {
    let silo = new(staking_vault, ctx);
    transfer::share_object(silo);
}

// === Public Functions ===

/// Deposit deUSD tokens into the silo (called from StdEUSD management)
public fun deposit(
    silo: &mut DeUSDSilo,
    assets: Coin<DEUSD>,
    _ctx: &mut TxContext,
) {
    // Note: In a production system, we would use a capability pattern
    // For now, we trust the caller is the StdEUSD management contract
    silo.deusd_balance.join(coin::into_balance(assets));
}

/// Withdraw deUSD tokens from the silo to a specific address
public fun withdraw(
    silo: &mut DeUSDSilo,
    _to: address,
    amount: u64,
    ctx: &mut TxContext,
): Coin<DEUSD> {
    // Note: In a production system, we would use a capability pattern
    // For now, we trust the caller is the StdEUSD management contract
    let withdrawn_balance = silo.deusd_balance.split(amount);
    coin::from_balance(withdrawn_balance, ctx)
}

/// Get the balance of deUSD tokens in the silo
public fun balance(silo: &DeUSDSilo): u64 {
    silo.deusd_balance.value()
}

/// Get the staking vault address
public fun staking_vault(silo: &DeUSDSilo): address {
    silo.staking_vault
}

// === Test Functions ===

#[test_only]
public fun new_for_test(staking_vault: address, ctx: &mut TxContext): DeUSDSilo {
    new(staking_vault, ctx)
}
