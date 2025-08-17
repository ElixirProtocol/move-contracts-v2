module elixir::deusd_lp_staking;

// === Imports ===

use std::type_name;
use std::type_name::TypeName;
use sui::balance;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::dynamic_field::{Self as df};
use sui::event;
use sui::table::{Self, Table};
use elixir::admin_cap::AdminCap;
use elixir::clock_utils;
use elixir::config::GlobalConfig;

// === Error codes ===

/// Invalid amount
const EInvalidAmount: u64 = 1;
/// No stake found for user
const ENoUserStake: u64 = 2;
/// No stake parameters found for token
const ENoStakeParameters: u64 = 3;
/// Invalid epoch
const EInvalidEpoch: u64 = 4;
/// Maximum cooldown period exceeded
const EMaxCooldownExceeded: u64 = 5;
/// Stake limit exceeded
const EStakeLimitExceeded: u64 = 6;
/// Cooldown period not over
const ECooldownNotOver: u64 = 7;
/// Invariant broken
const EInvariantBroken: u64 = 8;

// === Constants ===

/// Maximum cooldown period (90 days in seconds)
const MAX_COOLDOWN_PERIOD: u64 = 90 * 86400;

// === Structs ===

/// Main contract state
public struct DeUSDLPStakingManagement has key {
    id: UID,
    /// Tracks the current epoch
    current_epoch: u8,
    /// Tracks all stakes, indexed by user and LP token
    stakes: Table<address, Table<TypeName, StakeData>>,
    /// Tracks stake parameters for each LP token
    stake_parameters_by_token: Table<TypeName, StakeParameters>,
}

/// Individual stake data for a user and token
public struct StakeData has store, copy, drop {
    /// Amount currently staked and earning rewards
    staked_amount: u64,
    /// Amount cooling down (not earning rewards)
    cooling_down_amount: u64,
    /// Timestamp when cooldown started
    cooldown_start_timestamp: u64,
}

/// Parameters for staking a specific token
public struct StakeParameters has store, copy, drop {
    /// Epoch when this token is eligible for staking
    epoch: u8,
    /// Maximum amount that can be staked
    stake_limit: u64,
    /// Cooldown period in seconds
    cooldown: u64,
    /// Total amount currently staked
    total_staked: u64,
    /// Total amount currently cooling down
    total_cooling_down: u64,
}

/// Key for storing token balances in dynamic fields
public struct BalanceStoreKey<phantom T> has copy, drop, store {}

// === Events ===

public struct NewEpoch has copy, drop, store {
    new_epoch: u8,
    old_epoch: u8,
}

public struct StakeParametersUpdated has copy, drop, store {
    token: TypeName,
    epoch: u8,
    stake_limit: u64,
    cooldown: u64,
}

public struct Stake has copy, drop, store {
    user: address,
    token: TypeName,
    amount: u64,
}

public struct Unstake has copy, drop, store {
    user: address,
    token: TypeName,
    amount: u64,
}

public struct Withdraw has copy, drop, store {
    user: address,
    token: TypeName,
    amount: u64,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    let staking = DeUSDLPStakingManagement {
        id: object::new(ctx),
        current_epoch: 0,
        stakes: table::new(ctx),
        stake_parameters_by_token: table::new(ctx),
    };
    transfer::share_object(staking);
}

// === Public Functions ===

/// Owner can change epoch
public fun set_epoch(
    _: &AdminCap,
    management: &mut DeUSDLPStakingManagement,
    global_config: &GlobalConfig,
    new_epoch: u8,
) {
    global_config.check_package_version();
    assert!(new_epoch != management.current_epoch, EInvalidEpoch);

    let old_epoch = management.current_epoch;
    management.current_epoch = new_epoch;

    event::emit(NewEpoch { new_epoch, old_epoch });
}

/// Owner can add/update stake parameters for a given LP token
public fun update_stake_parameters<T>(
    _: &AdminCap,
    management: &mut DeUSDLPStakingManagement,
    global_config: &GlobalConfig,
    epoch: u8,
    stake_limit: u64,
    cooldown: u64,
) {
    global_config.check_package_version();
    assert!(cooldown <= MAX_COOLDOWN_PERIOD, EMaxCooldownExceeded);

    let token_type = type_name::get<T>();

    if (management.stake_parameters_by_token.contains(token_type)) {
        let params = management.stake_parameters_by_token.borrow_mut(token_type);
        params.epoch = epoch;
        params.stake_limit = stake_limit;
        params.cooldown = cooldown;
    } else {
        let params = StakeParameters {
            epoch,
            stake_limit,
            cooldown,
            total_staked: 0,
            total_cooling_down: 0,
        };
        management.stake_parameters_by_token.add(token_type, params);
    };

    event::emit(StakeParametersUpdated {
        token: token_type,
        epoch,
        stake_limit,
        cooldown,
    });
}

/// Users can stake LP tokens to earn potions
public fun stake<T>(
    management: &mut DeUSDLPStakingManagement,
    global_config: &GlobalConfig,
    token: Coin<T>,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();

    let amount = token.value();
    assert!(amount > 0, EInvalidAmount);

    let token_type = type_name::get<T>();
    assert!(management.stake_parameters_by_token.contains(token_type), ENoStakeParameters);

    let params = management.stake_parameters_by_token.borrow_mut(token_type);
    // Can only stake when it is the correct epoch
    assert!(management.current_epoch == params.epoch, EInvalidEpoch);
    assert!(params.total_staked + amount <= params.stake_limit, EStakeLimitExceeded);

    params.total_staked = params.total_staked + amount;

    let sender = ctx.sender();

    // Initialize user stake data if doesn't exist
    if (!management.stakes.contains(sender)) {
        management.stakes.add(sender, table::new(ctx));
    };

    let user_stakes = management.stakes.borrow_mut(sender);
    if (user_stakes.contains(token_type)) {
        let stake_data = user_stakes.borrow_mut(token_type);
        stake_data.staked_amount = stake_data.staked_amount + amount;
    } else {
        user_stakes.add(token_type, StakeData {
            staked_amount: amount,
            cooling_down_amount: 0,
            cooldown_start_timestamp: 0,
        });
    };

    // Store the tokens in the contract balance
    let contract_balance = get_or_create_balance_store<T>(management);
    contract_balance.join(coin::into_balance(token));

    check_invariant<T>(management);

    event::emit(Stake {
        user: sender,
        token: token_type,
        amount,
    });
}

/// Users can unstake LP tokens to initiate the cooldown period
public fun unstake<T>(
    management: &mut DeUSDLPStakingManagement,
    global_config: &GlobalConfig,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert!(amount > 0, EInvalidAmount);

    let token_type = type_name::get<T>();
    let sender = ctx.sender();

    assert!(management.stakes.contains(sender), ENoUserStake);
    let user_stakes = management.stakes.borrow_mut(sender);
    assert!(user_stakes.contains(token_type), ENoUserStake);

    let stake_data = user_stakes.borrow_mut(token_type);
    assert!(stake_data.staked_amount >= amount, EInvalidAmount);

    stake_data.staked_amount = stake_data.staked_amount - amount;
    stake_data.cooling_down_amount = stake_data.cooling_down_amount + amount;
    stake_data.cooldown_start_timestamp = clock_utils::timestamp_seconds(clock);

    let params = management.stake_parameters_by_token.borrow_mut(token_type);
    params.total_staked = params.total_staked - amount;
    params.total_cooling_down = params.total_cooling_down + amount;

    check_invariant<T>(management);

    event::emit(Unstake {
        user: sender,
        token: token_type,
        amount,
    });
}

#[allow(lint(self_transfer))]
/// Users can withdraw LP tokens after the cooldown period has passed
public fun withdraw<T>(
    management: &mut DeUSDLPStakingManagement,
    global_config: &GlobalConfig,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert!(amount > 0, EInvalidAmount);

    let token_type = type_name::get<T>();
    let sender = ctx.sender();

    assert!(management.stakes.contains(sender), ENoUserStake);
    let user_stakes = management.stakes.borrow_mut(sender);
    assert!(user_stakes.contains(token_type), ENoUserStake);

    let stake_data = user_stakes.borrow_mut(token_type);
    assert!(stake_data.cooling_down_amount >= amount, EInvalidAmount);

    let params = management.stake_parameters_by_token.borrow(token_type);
    let current_time = clock_utils::timestamp_seconds(clock);
    assert!(current_time >= stake_data.cooldown_start_timestamp + params.cooldown, ECooldownNotOver);

    stake_data.cooling_down_amount = stake_data.cooling_down_amount - amount;

    let params_mut = management.stake_parameters_by_token.borrow_mut(token_type);
    params_mut.total_cooling_down = params_mut.total_cooling_down - amount;

    // Transfer tokens back to user
    let contract_balance = get_or_create_balance_store<T>(management);
    let withdrawn_balance = contract_balance.split(amount);
    transfer::public_transfer(coin::from_balance(withdrawn_balance, ctx), sender);

    check_invariant<T>(management);

    event::emit(Withdraw {
        user: sender,
        token: token_type,
        amount,
    });
}

// === View Functions ===

/// Get current epoch
public fun get_current_epoch(management: &DeUSDLPStakingManagement): u8 {
    management.current_epoch
}

/// Get stake data for a user and token
/// Returns (staked_amount, cooling_down_amount, cooldown_start_timestamp)
public fun get_stake_data<T>(management: &DeUSDLPStakingManagement, user: address): (u64, u64, u64) {
    let token_type = type_name::get<T>();

    if (!management.stakes.contains(user)) {
        return (0, 0, 0)
    };

    let user_stakes = management.stakes.borrow(user);
    if (!user_stakes.contains(token_type)) {
        return (0, 0, 0)
    };

    let stake_data = user_stakes.borrow(token_type);
    (stake_data.staked_amount, stake_data.cooling_down_amount, stake_data.cooldown_start_timestamp)
}

/// Get stake parameters for a token
/// Returns (epoch, stake_limit, cooldown, total_staked, total_cooling_down)
public fun get_stake_parameters<T>(management: &DeUSDLPStakingManagement): (u8, u64, u64, u64, u64) {
    let token_type = type_name::get<T>();

    if (!management.stake_parameters_by_token.contains(token_type)) {
        return (0, 0, 0, 0, 0)
    };

    let params = management.stake_parameters_by_token.borrow(token_type);
    (params.epoch, params.stake_limit, params.cooldown, params.total_staked, params.total_cooling_down)
}

/// Get the total balance of a specific token held by the contract
/// Returns the balance of the token in the contract
public fun get_balance<T>(management: &DeUSDLPStakingManagement): u64 {
    if (df::exists_(&management.id, BalanceStoreKey<T> {})) {
        let balance_ref = df::borrow<BalanceStoreKey<T>, Balance<T>>(&management.id, BalanceStoreKey<T> {});
        balance_ref.value()
    } else {
        0
    }
}

// === Helper Functions ===

fun get_or_create_balance_store<T>(management: &mut DeUSDLPStakingManagement): &mut Balance<T> {
    if (!df::exists_(&management.id, BalanceStoreKey<T> {})) {
        df::add(&mut management.id, BalanceStoreKey<T> {}, balance::zero<T>());
    };
    df::borrow_mut(&mut management.id, BalanceStoreKey<T> {})
}

/// Checks that the invariant is not broken.
/// The invariant is that the contract should never hold less of a token than the total staked and cooling down.
/// We intentionally do not pass in the stake parameters because
/// we want to ensure that the invariant is checked against the current state of the contract.
fun check_invariant<T>(mangement: &DeUSDLPStakingManagement) {
    let token_type = type_name::get<T>();
    let stake_parameters = mangement.stake_parameters_by_token.borrow(token_type);

    let contract_balance = if (df::exists_(&mangement.id, BalanceStoreKey<T> {})) {
        let balance_ref = df::borrow<BalanceStoreKey<T>, Balance<T>>(&mangement.id, BalanceStoreKey<T> {});
        balance_ref.value()
    } else {
        0
    };

    assert!(contract_balance >= stake_parameters.total_staked + stake_parameters.total_cooling_down, EInvariantBroken);
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun create_for_test(ctx: &mut TxContext): DeUSDLPStakingManagement {
    DeUSDLPStakingManagement {
        id: object::new(ctx),
        current_epoch: 0,
        stakes: table::new(ctx),
        stake_parameters_by_token: table::new(ctx),
    }
}

#[test_only]
public fun destroy_for_test(management: DeUSDLPStakingManagement) {
    let DeUSDLPStakingManagement { id, current_epoch: _, stakes, stake_parameters_by_token } = management;
    id.delete();
    sui::test_utils::destroy(stakes);
    sui::test_utils::destroy(stake_parameters_by_token);
}

#[test_only]
public fun run_invariant_check_for_test<T>(management: &DeUSDLPStakingManagement) {
    check_invariant<T>(management);
}

#[test_only]
public fun update_stake_parameters_for_test<T>(
    management: &mut DeUSDLPStakingManagement,
    artificial_total_staked: u64,
    artificial_total_cooling_down: u64,
) {
    let token_type = type_name::get<T>();
    if (management.stake_parameters_by_token.contains(token_type)) {
        let params = management.stake_parameters_by_token.borrow_mut(token_type);
        params.total_staked = artificial_total_staked;
        params.total_cooling_down = artificial_total_cooling_down;
    }
}
