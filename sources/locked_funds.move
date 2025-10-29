/// Sui Move does not provide a built-in mechanism like ERC20's `approve` in Solidity, which allows contracts
/// or other accounts to transfer tokens on behalf of the owner (`transferFrom` and `burnFrom` functions).
/// To enable this functionality in Sui Move, a custom contract is required.
/// This contract locks users' funds so that operators can use them for other actions,
/// such as minting or burning `deUSD`.
module elixir::locked_funds;

// === Imports ===

use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance};
use sui::bcs;
use sui::coin::{Self, Coin};
use sui::dynamic_field as df;
use sui::event;
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};
use elixir::config::GlobalConfig;

// === Error codes ===

const EZeroAmount: u64 = 1;
const ENotEnoughAmount: u64 = 2;

// === Structs ===

public struct LockedFundsManagement has key {
    id: UID,
    /// Maps owner address to deposited collateral coin types.
    user_collateral_coin_types: Table<address, VecSet<TypeName>>,
}

public struct BalanceStore<phantom T> has store {
    balance: Balance<T>,
}

// === Events ===

public struct Deposit has copy, drop, store {
    owner: address,
    amount: u64,
    coin_type: TypeName,
}

public struct Withdraw has copy, drop, store {
    owner: address,
    amount: u64,
    coin_type: TypeName,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    let management = LockedFundsManagement {
        id: object::new(ctx),
        user_collateral_coin_types: table::new(ctx),
    };
    transfer::share_object(management);
}

// === Public Functions ===

public fun deposit<T>(
    management: &mut LockedFundsManagement,
    global_config: &GlobalConfig,
    coins: Coin<T>,
    ctx: &mut TxContext
) {
    global_config.check_package_version();

    let coin_amount = coins.value();
    assert!(coin_amount > 0, EZeroAmount);

    let owner = ctx.sender();
    let balance_store = get_or_create_balance_store_mut<T>(management, owner);
    balance_store.balance.join(coin::into_balance(coins));

    update_user_collateral_coin_types<T>(management, owner, balance_store.balance.value());

    event::emit(Deposit {
        owner,
        amount: coin_amount,
        coin_type: type_name::get<T>(),
    });
}

#[allow(lint(self_transfer))]
public fun withdraw<T>(
    management: &mut LockedFundsManagement,
    global_config: &GlobalConfig,
    amount: u64,
    ctx: &mut TxContext
) {
    global_config.check_package_version();

    assert!(amount > 0, EZeroAmount);

    let owner = ctx.sender();
    let balance_store = get_or_create_balance_store_mut<T>(management, owner);

    assert!(balance_store.balance.value() >= amount, ENotEnoughAmount);

    let withdrawn_balance = balance_store.balance.split(amount);
    let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);
    transfer::public_transfer(withdrawn_coin, owner);

    update_user_collateral_coin_types<T>(management, owner, balance_store.balance.value());

    event::emit(Withdraw {
        owner,
        amount,
        coin_type: type_name::get<T>(),
    });
}

// === View Functions ===

public fun get_user_collateral_coin_types(
    management: &LockedFundsManagement,
    owner: address,
): vector<TypeName> {
    if (!table::contains(&management.user_collateral_coin_types, owner)) {
        return vector::empty()
    };

    let coin_types = table::borrow(&management.user_collateral_coin_types, owner);
    let keys = coin_types.keys();
    let mut result = vector::empty<TypeName>();
    let mut i = 0;
    while (i < keys.length()) {
        result.push_back(keys[i]);
        i = i + 1;
    };
    result
}

public fun get_user_collateral_amount<T>(
    management: &LockedFundsManagement,
    owner: address,
): u64 {
    let balance_key = get_balance_store_key<T>(owner);
    if (!df::exists_(&management.id, balance_key)) {
        return 0
    };

    let balance_store = df::borrow<vector<u8>, BalanceStore<T>>(&management.id, balance_key);
    balance_store.balance.value()
}

// === Package Functions ===

public(package) fun withdraw_internal<T>(
    management: &mut LockedFundsManagement,
    owner: address,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(amount > 0, EZeroAmount);

    let balance_key = get_balance_store_key<T>(owner);
    assert!(df::exists_(&management.id, balance_key), ENotEnoughAmount);

    let balance_store = df::borrow_mut<vector<u8>, BalanceStore<T>>(&mut management.id, balance_key);
    assert!(balance_store.balance.value() >= amount, ENotEnoughAmount);

    let collateral = coin::from_balance(balance_store.balance.split(amount), ctx);

    update_user_collateral_coin_types<T>(management, owner, balance_store.balance.value());

    collateral
}

// === Helper Functions ===

fun get_or_create_balance_store_mut<T>(
    management: &mut LockedFundsManagement,
    owner: address,
): &mut BalanceStore<T> {
    let balance_key = get_balance_store_key<T>(owner);
    if (!df::exists_(&management.id, balance_key)) {
        df::add(
            &mut management.id,
            balance_key,
            BalanceStore {
                balance: balance::zero<T>(),
            },
        );
    };

    df::borrow_mut(&mut management.id, balance_key)
}

fun get_balance_store_key<T>(owner: address): vector<u8> {
    let mut key = bcs::to_bytes(&type_name::get<T>().into_string());
    key.append(bcs::to_bytes(&owner));
    key
}

fun update_user_collateral_coin_types<T>(
    management: &mut LockedFundsManagement,
    owner: address,
    current_balance: u64,
) {
    let coin_type = type_name::get<T>();
    if (current_balance != 0) {
        if (!table::contains(&management.user_collateral_coin_types, owner)) {
            table::add(&mut management.user_collateral_coin_types, owner, vec_set::empty());
        };
        let coin_types = table::borrow_mut(&mut management.user_collateral_coin_types, owner);
        if (!coin_types.contains(&coin_type)) {
            coin_types.insert(coin_type);
        }
    } else {
        if (table::contains(&management.user_collateral_coin_types, owner)) {
            let coin_types = table::borrow_mut(&mut management.user_collateral_coin_types, owner);
            if (coin_types.contains(&coin_type)) {
                coin_types.remove(&coin_type);
            }
        };

        let balance_key = get_balance_store_key<T>(owner);
        if (df::exists_(&management.id, balance_key)) {
            let balance_store = df::remove<vector<u8>, BalanceStore<T>>(&mut management.id, balance_key);
            let BalanceStore<T> { balance } = balance_store;
            balance::destroy_zero(balance);
        };
    }
}

// === Tests ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(ctx);
}
