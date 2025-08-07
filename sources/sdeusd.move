/// The stdeUSD contract allows users to stake deUSD tokens and earn a portion of protocol LST and
/// perpetual yield that is allocated to stakers by the Elixir Foundation voted yield distribution algorithm.
/// The algorithm seeks to balance the stability of the protocol by funding
/// the protocol's insurance fund, DAO activities, and rewarding stakers with a portion of the protocol's yield.
#[allow(unused_const)]
module elixir::sdeusd;

// === Imports ===

use elixir::math_u64;
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin, TreasuryCap, DenyCapV2};
use sui::balance::{Self, Balance};
use sui::deny_list::DenyList;
use sui::event;
use elixir::set::{Self, Set};
use elixir::config::GlobalConfig;
use elixir::admin_cap::AdminCap;
use elixir::deusd::DEUSD;
use elixir::deusd_silo::{Self, DeUSDSilo};
use elixir::roles;

// === Error codes ===

/// The caller is not authorized to perform this action.
const ENotAuthorized: u64 = 1;
/// Zero amount.
const EZeroAmount: u64 = 2;
/// Cannot blacklist the owner.
const ECantBlacklistOwner: u64 = 3;
/// Operation not allowed.
const EOperationNotAllowed: u64 = 4;
/// Invalid cooldown.
const EInvalidCooldown: u64 = 5;
/// Excessive withdraw amount.
const EExcessiveWithdrawAmount: u64 = 6;
/// Excessive redeem amount.
const EExcessiveRedeemAmount: u64 = 7;
/// Minimum shares violation.
const EMinSharesViolation: u64 = 8;
/// Still vesting.
const EStillVesting: u64 = 9;
/// Invalid token (cannot rescue the underlying asset).
const EInvalidToken: u64 = 10;
/// Invalid zero address.
const EInvalidZeroAddress: u64 = 11;

// === Constants ===

/// The vesting period over which rewards become available to stakers (8 hours in milliseconds)
const VESTING_PERIOD: u64 = 8 * 3600 * 1000;
/// Minimum non-zero shares amount to prevent donation attack
const MIN_SHARES: u64 = 1_000_000; // 1 token with 6 decimals
/// Maximum staking cooldown duration (90 days in milliseconds)
const MAX_COOLDOWN_DURATION: u64 = 90 * 86400 * 1000;

// === Structs ===

/// The main staked deUSD token
public struct SDEUSD has drop {}

/// User cooldown information
public struct UserCooldown has store, copy, drop {
    cooldown_end: u64,
    underlying_amount: u64,
}

/// Main management struct for the staked deUSD contract
public struct StdeUSDManagement has key {
    id: UID,
    /// Treasury cap for minting/burning stdeUSD tokens
    treasury_cap: TreasuryCap<SDEUSD>,
    /// Deny cap for stdeUSD tokens
    deny_cap: DenyCapV2<SDEUSD>,
    /// Balance of deUSD tokens held by the contract
    deusd_balance: Balance<DEUSD>,
    /// The amount of the last asset distribution
    vesting_amount: u64,
    /// The timestamp of the last asset distribution
    last_distribution_timestamp: u64,
    /// Current cooldown time period
    cooldown_duration: u64,
    /// Total supply of stdeUSD tokens
    total_supply: u64,
    /// Soft restricted stakers (cannot stake)
    soft_restricted_stakers: Set<address>,
    /// Full restricted stakers (cannot transfer, stake, or unstake)
    full_restricted_stakers: Set<address>,
}

/// User cooldowns mapping
public struct UserCooldowns has key {
    id: UID,
    cooldowns: vector<UserCooldownEntry>,
}

public struct UserCooldownEntry has store, drop {
    user: address,
    cooldown: UserCooldown,
}

/// User balances mapping to track stdeUSD balances per user
public struct UserBalances has key {
    id: UID,
    balances: vector<UserBalance>,
}

public struct UserBalance has store {
    user: address,
    balance: u64,
}

// === Events ===

public struct RewardsReceived has copy, drop, store {
    amount: u64,
}

public struct CooldownDurationUpdated has copy, drop, store {
    previous_duration: u64,
    new_duration: u64,
}

public struct Deposit has copy, drop, store {
    caller: address,
    receiver: address,
    assets: u64,
    shares: u64,
}

public struct Withdraw has copy, drop, store {
    caller: address,
    receiver: address,
    owner: address,
    assets: u64,
    shares: u64,
}

public struct CooldownStarted has copy, drop, store {
    user: address,
    assets: u64,
    shares: u64,
    cooldown_end: u64,
}

public struct Unstaked has copy, drop, store {
    user: address,
    receiver: address,
    assets: u64,
}

public struct UserBlacklisted has copy, drop, store {
    sender: address,
    user: address,
    is_full_blacklisting: bool,
}

public struct UserUnblacklisted has copy, drop, store {
    sender: address,
    user: address,
    is_full_blacklisting: bool,
}

// === Initialization ===

/// Initializes the stdeUSD contract, creating the treasury cap, management, user cooldowns, and user balances objects.
fun init(witness: SDEUSD, ctx: &mut TxContext) {
    let (treasury_cap, deny_cap, metadata) = coin::create_regulated_currency_v2(
        witness,
        6,
        b"stdeUSD",
        b"Staked deUSD",
        b"Staked deUSD tokens for earning yield",
        option::none(),
        true,
        ctx
    );
    transfer::public_freeze_object(metadata);

    let management = StdeUSDManagement {
        id: object::new(ctx),
        treasury_cap,
        deny_cap,
        deusd_balance: balance::zero(),
        vesting_amount: 0,
        last_distribution_timestamp: 0,
        cooldown_duration: MAX_COOLDOWN_DURATION,
        total_supply: 0,
        soft_restricted_stakers: set::new(ctx),
        full_restricted_stakers: set::new(ctx),
    };
    transfer::share_object(management);

    let user_cooldowns = UserCooldowns {
        id: object::new(ctx),
        cooldowns: vector::empty(),
    };
    transfer::share_object(user_cooldowns);

    let user_balances = UserBalances {
        id: object::new(ctx),
        balances: vector::empty(),
    };
    transfer::share_object(user_balances);

    deusd_silo::create_and_share(ctx.sender(), ctx);
}

// === Public Functions ===

/// Allows a rewarder to transfer deUSD rewards into the contract and updates vesting state.
public fun transfer_in_rewards(
    management: &mut StdeUSDManagement,
    global_config: &GlobalConfig,
    rewards: Coin<DEUSD>,
    clock: &Clock,
    ctx: &TxContext,
) {
    global_config.check_package_version();
    assert!(global_config.has_role(ctx.sender(), roles::role_rewarder()), ENotAuthorized);

    let amount = rewards.value();
    assert!(amount > 0, EZeroAmount);

    update_vesting_amount(management, amount, clock);
    management.deusd_balance.join(coin::into_balance(rewards));

    event::emit(RewardsReceived { amount });
}

/// Adds an address to the blacklist, either as soft or full restricted.
/// Only callable by blacklist managers.
public fun add_to_blacklist(
    management: &mut StdeUSDManagement,
    global_config: &GlobalConfig,
    deny_list: &mut DenyList,
    target: address,
    is_full_blacklisting: bool,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert!(global_config.has_role(ctx.sender(), roles::role_blacklist_manager()), ENotAuthorized);

    if (is_full_blacklisting) {
        management.full_restricted_stakers.add(target);
        coin::deny_list_v2_add(deny_list, &mut management.deny_cap, target, ctx);
    } else {
        management.soft_restricted_stakers.add(target);
    };

    event::emit(UserBlacklisted {
        sender: ctx.sender(),
        user: target,
        is_full_blacklisting,
    });
}

/// Removes an address from the blacklist (soft or full). Only callable by blacklist managers.
public fun remove_from_blacklist(
    management: &mut StdeUSDManagement,
    global_config: &GlobalConfig,
    deny_list: &mut DenyList,
    target: address,
    is_full_blacklisting: bool,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert!(global_config.has_role(ctx.sender(), roles::role_blacklist_manager()), ENotAuthorized);

    if (is_full_blacklisting) {
        if (management.full_restricted_stakers.contains(target)) {
            management.full_restricted_stakers.remove(target);
            coin::deny_list_v2_add(deny_list, &mut management.deny_cap, target, ctx);
        };
    } else {
        if (management.soft_restricted_stakers.contains(target)) {
            management.soft_restricted_stakers.remove(target);
        };
    };

    event::emit(UserUnblacklisted {
        sender: ctx.sender(),
        user: target,
        is_full_blacklisting,
    });
}

public fun withdraw(
    management: &mut StdeUSDManagement,
    global_config: &GlobalConfig,
    user_balances: &mut UserBalances,
    assets: Coin<DEUSD>,
    receiver: address,
    owner: address,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<DEUSD>, Coin<SDEUSD>) {
    global_config.check_package_version();
    assert!(management.cooldown_duration == 0, EOperationNotAllowed);

    // TODO: block if user is full restricted

    let asset_amount = assets.value();

    let shares = preview_withdraw(management, asset_amount, clock);
    let (withdrawn_assets, burned_shares) = internal_withdraw(
        management, 
        user_balances, 
        ctx.sender(), 
        receiver, 
        owner, 
        assets, 
        shares, 
        ctx
    );

    (withdrawn_assets, burned_shares)
}

/// Deposits deUSD and mints sdeUSD shares to the receiver. Fails if caller or receiver is soft restricted.
public fun deposit(
    management: &mut StdeUSDManagement,
    global_config: &GlobalConfig,
    user_balances: &mut UserBalances,
    assets: Coin<DEUSD>,
    receiver: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SDEUSD> {
    global_config.check_package_version();

    let caller = ctx.sender();
    assert!(!is_soft_restricted_staker(management, caller), EOperationNotAllowed);
    assert!(!is_soft_restricted_staker(management, receiver), EOperationNotAllowed);

    let asset_amount = assets.value();
    assert!(asset_amount > 0, EZeroAmount);

    let shares = preview_deposit(management, asset_amount, clock);
    assert!(shares > 0, EZeroAmount);

    management.deusd_balance.join(coin::into_balance(assets));
    management.total_supply = management.total_supply + shares;

    // Update user balance
    update_user_balance(user_balances, receiver, shares, true);

    let shares_coin = coin::mint(&mut management.treasury_cap, shares, ctx);

    check_min_shares(management);

    event::emit(Deposit {
        caller,
        receiver,
        assets: asset_amount,
        shares,
    });

    shares_coin
}

/// Standard ERC4626-style mint
public fun mint(
    management: &mut StdeUSDManagement,
    global_config: &GlobalConfig,
    user_balances: &mut UserBalances,
    shares: u64,
    receiver: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SDEUSD> {
    global_config.check_package_version();

    let caller = ctx.sender();
    assert!(!is_soft_restricted_staker(management, caller), EOperationNotAllowed);
    assert!(!is_soft_restricted_staker(management, receiver), EOperationNotAllowed);

    let assets = preview_mint(management, shares, clock);
    assert!(assets > 0, EZeroAmount);
    assert!(shares > 0, EZeroAmount);

    management.total_supply = management.total_supply + shares;
    update_user_balance(user_balances, receiver, shares, true);

    let shares_coin = coin::mint(&mut management.treasury_cap, shares, ctx);

    check_min_shares(management);

    event::emit(Deposit {
        caller,
        receiver,
        assets,
        shares,
    });

    shares_coin
}

/// Starts a cooldown for withdrawal by burning shares for deUSD, which is held in the silo until cooldown ends.
public fun cooldown_assets(
    management: &mut StdeUSDManagement,
    global_config: &GlobalConfig,
    user_cooldowns: &mut UserCooldowns,
    user_balances: &mut UserBalances,
    silo: &mut DeUSDSilo,
    assets: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): u64 {
    global_config.check_package_version();
    assert!(management.cooldown_duration > 0, EOperationNotAllowed);

    let caller = ctx.sender();
    assert!(assets <= max_withdraw_user(management, user_balances, caller, clock), EExcessiveWithdrawAmount);

    let shares = preview_withdraw(management, assets, clock);
    let cooldown_end = clock::timestamp_ms(clock) + management.cooldown_duration;

    // Update user cooldown
    update_user_cooldown(user_cooldowns, caller, cooldown_end, assets, shares);

    // Update user balance (decrease)
    update_user_balance(user_balances, caller, shares, false);

    // Transfer assets to silo
    let asset_coin = coin::from_balance(management.deusd_balance.split(assets), ctx);
    deusd_silo::deposit(silo, asset_coin, ctx);

    // Update total supply
    management.total_supply = management.total_supply - shares;

    event::emit(CooldownStarted {
        user: caller,
        assets,
        shares,
        cooldown_end,
    });

    shares
}

/// Starts a cooldown by burning a specific amount of shares
public fun cooldown_shares(
    management: &mut StdeUSDManagement,
    global_config: &GlobalConfig,
    user_cooldowns: &mut UserCooldowns,
    user_balances: &mut UserBalances,
    silo: &mut DeUSDSilo,
    shares: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): u64 {
    global_config.check_package_version();
    assert!(management.cooldown_duration > 0, EOperationNotAllowed);

    let caller = ctx.sender();
    assert!(shares <= max_redeem_user(management, user_balances, caller), EExcessiveRedeemAmount);

    let assets = preview_redeem(management, shares, clock);
    let cooldown_end = clock::timestamp_ms(clock) + management.cooldown_duration;

    // Update user cooldown
    update_user_cooldown(user_cooldowns, caller, cooldown_end, assets, shares);

    // Update user balance (decrease)
    update_user_balance(user_balances, caller, shares, false);

    // Transfer assets to silo
    let asset_coin = coin::from_balance(management.deusd_balance.split(assets), ctx);
    deusd_silo::deposit(silo, asset_coin, ctx);

    // Update total supply
    management.total_supply = management.total_supply - shares;

    event::emit(CooldownStarted {
        user: caller,
        assets,
        shares,
        cooldown_end,
    });

    assets
}

/// Claims unstaked deUSD from the silo after cooldown period has ended.
public fun unstake(
    management: &StdeUSDManagement,
    global_config: &GlobalConfig,
    user_cooldowns: &mut UserCooldowns,
    silo: &mut DeUSDSilo,
    receiver: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<DEUSD> {
    global_config.check_package_version();
    
    let caller = ctx.sender();
    let cooldown = get_user_cooldown(user_cooldowns, caller);

    let current_time = clock::timestamp_ms(clock);
    assert!(
        current_time >= cooldown.cooldown_end || management.cooldown_duration == 0,
        EInvalidCooldown
    );

    let assets = cooldown.underlying_amount;

    // Clear user cooldown
    clear_user_cooldown(user_cooldowns, caller);

    // Withdraw from silo
    let asset_coin = deusd_silo::withdraw(silo, receiver, assets, ctx);

    event::emit(Unstaked {
        user: caller,
        receiver,
        assets,
    });

    asset_coin
}

/// Sets the cooldown duration for withdrawals. Only callable by admin.
public fun set_cooldown_duration(
    _: &AdminCap,
    management: &mut StdeUSDManagement,
    global_config: &GlobalConfig,
    duration: u64,
    _ctx: &TxContext,
) {
    global_config.check_package_version();

    assert!(duration <= MAX_COOLDOWN_DURATION, EInvalidCooldown);

    let previous_duration = management.cooldown_duration;
    management.cooldown_duration = duration;

    event::emit(CooldownDurationUpdated {
        previous_duration,
        new_duration: duration,
    });
}

// === View Functions ===

/// Returns the total deUSD assets available to stakers (vested balance).
public fun total_assets(management: &StdeUSDManagement, clock: &Clock): u64 {
    let total_balance = management.deusd_balance.value();
    let unvested = get_unvested_amount(management, clock);
    if (total_balance >= unvested) {
        total_balance - unvested
    } else {
        0
    }
}

/// Returns the amount of deUSD that is still vesting and not yet available to stakers.
public fun get_unvested_amount(management: &StdeUSDManagement, clock: &Clock): u64 {
    let current_time = clock::timestamp_ms(clock);
    let time_since_last_distribution = current_time - management.last_distribution_timestamp;

    if (time_since_last_distribution >= VESTING_PERIOD) {
        return 0
    };

    math_u64::mul_div(VESTING_PERIOD - time_since_last_distribution, management.vesting_amount, VESTING_PERIOD)
}

/// Calculates the number of stdeUSD shares to mint for a given deposit amount.
public fun preview_deposit(management: &StdeUSDManagement, assets: u64, clock: &Clock): u64 {
    let total_supply = management.total_supply;
    if (total_supply == 0) {
        assets
    } else {
        let total_assets = total_assets(management, clock);
        if (total_assets == 0) {
            assets
        } else {
            (assets * total_supply) / total_assets
        }
    }
}

/// Calculates the amount of assets required to mint a specific number of shares
public fun preview_mint(management: &StdeUSDManagement, shares: u64, clock: &Clock): u64 {
    let total_supply = management.total_supply;
    if (total_supply == 0) {
        shares
    } else {
        let total_assets = total_assets(management, clock);
        // Round up using the ceiling division pattern
        ((shares * total_assets) + total_supply - 1) / total_supply
    }
}

/// Calculates the amount of deUSD to return for a given number of stdeUSD shares.
public fun preview_redeem(management: &StdeUSDManagement, shares: u64, clock: &Clock): u64 {
    let total_supply = management.total_supply;
    if (total_supply == 0) {
        0
    } else {
        let total_assets = total_assets(management, clock);
        (shares * total_assets) / total_supply
    }
}

/// Calculates the number of shares to burn for a specific amount of assets
public fun preview_withdraw(management: &StdeUSDManagement, assets: u64, clock: &Clock): u64 {
    let total_supply = management.total_supply;
    if (total_supply == 0) {
        assets
    } else {
        let total_assets = total_assets(management, clock);
        if (total_assets == 0) {
            assets
        } else {
            // Round up using the ceiling division pattern
            ((assets * total_supply) + total_assets - 1) / total_assets
        }
    }
}

/// Returns the maximum amount of deUSD a user can withdraw.
public fun max_withdraw_user(
    management: &StdeUSDManagement, 
    user_balances: &UserBalances, 
    user: address,
    clock: &Clock
): u64 {
    let user_balance = get_user_balance(user_balances, user);
    preview_redeem(management, user_balance, clock)
}

/// Returns the maximum number of shares a user can redeem
public fun max_redeem_user(
    _management: &StdeUSDManagement, 
    user_balances: &UserBalances, 
    user: address
): u64 {
    get_user_balance(user_balances, user)
}

/// Get user's current cooldown information
public fun get_user_cooldown_info(user_cooldowns: &UserCooldowns, user: address): UserCooldown {
    get_user_cooldown(user_cooldowns, user)
}

/// Get the underlying amount from a cooldown
public fun cooldown_underlying_amount(cooldown: &UserCooldown): u64 {
    cooldown.underlying_amount
}

/// Get the cooldown end time
public fun cooldown_end_time(cooldown: &UserCooldown): u64 {
    cooldown.cooldown_end
}

/// Get user's stdeUSD balance
public fun get_user_balance_info(user_balances: &UserBalances, user: address): u64 {
    get_user_balance(user_balances, user)
}

/// Get total supply of stdeUSD
public fun total_supply(management: &StdeUSDManagement): u64 {
    management.total_supply
}

/// Get current cooldown duration
public fun cooldown_duration(management: &StdeUSDManagement): u64 {
    management.cooldown_duration
}

/// Check if a user is soft restricted
public fun is_soft_restricted(management: &StdeUSDManagement, user: address): bool {
    is_soft_restricted_staker(management, user)
}

/// Check if a user is full restricted
public fun is_full_restricted(management: &StdeUSDManagement, user: address): bool {
    is_full_restricted_staker(management, user)
}

// === Helper Functions ===

fun is_soft_restricted_staker(management: &StdeUSDManagement, user: address): bool {
    management.soft_restricted_stakers.contains(user)
}

fun is_full_restricted_staker(management: &StdeUSDManagement, user: address): bool {
    management.full_restricted_stakers.contains(user)
}

fun update_vesting_amount(management: &mut StdeUSDManagement, new_vesting_amount: u64, clock: &Clock) {
    assert!(get_unvested_amount(management, clock) == 0, EStillVesting);

    management.vesting_amount = new_vesting_amount;
    management.last_distribution_timestamp = clock::timestamp_ms(clock);
}

fun check_min_shares(management: &StdeUSDManagement) {
    let total_supply = management.total_supply;
    assert!(total_supply == 0 || total_supply >= MIN_SHARES, EMinSharesViolation);
}

fun internal_withdraw(
    management: &mut StdeUSDManagement,
    user_balances: &mut UserBalances,
    caller: address,
    receiver: address,
    owner: address,
    assets: u64,
    shares: u64,
    ctx: &mut TxContext,
): (Coin<DEUSD>, Coin<SDEUSD>) {
    assert!(assets > 0, EZeroAmount);
    assert!(shares > 0, EZeroAmount);

    // Check restrictions
    assert!(!is_full_restricted_staker(management, caller), EOperationNotAllowed);
    assert!(!is_full_restricted_staker(management, receiver), EOperationNotAllowed);
    assert!(!is_full_restricted_staker(management, owner), EOperationNotAllowed);

    // Update user balance
    update_user_balance(user_balances, owner, shares, false);
    management.total_supply = management.total_supply - shares;

    // Transfer assets
    let asset_coin = coin::from_balance(management.deusd_balance.split(assets), ctx);
    let burned_shares = coin::mint(&mut management.treasury_cap, 0, ctx); // Placeholder

    check_min_shares(management);

    event::emit(Withdraw {
        caller,
        receiver,
        owner,
        assets,
        shares,
    });

    (asset_coin, burned_shares)
}

fun get_user_cooldown(user_cooldowns: &UserCooldowns, user: address): UserCooldown {
    let cooldowns = &user_cooldowns.cooldowns;
    let len = vector::length(cooldowns);
    let mut i = 0;

    while (i < len) {
        let entry = vector::borrow(cooldowns, i);
        if (entry.user == user) {
            return entry.cooldown
        };
        i = i + 1;
    };

    // Return default cooldown if not found
    UserCooldown {
        cooldown_end: 0,
        underlying_amount: 0,
    }
}

fun update_user_cooldown(
    user_cooldowns: &mut UserCooldowns,
    user: address,
    cooldown_end: u64,
    amount: u64,
    _shares: u64,
) {
    let cooldowns = &mut user_cooldowns.cooldowns;
    let len = vector::length(cooldowns);
    let mut i = 0;
    let mut found = false;

    while (i < len) {
        let entry = vector::borrow_mut(cooldowns, i);
        if (entry.user == user) {
            entry.cooldown.cooldown_end = cooldown_end;
            entry.cooldown.underlying_amount = entry.cooldown.underlying_amount + amount;
            found = true;
            break
        };
        i = i + 1;
    };

    if (!found) {
        let new_entry = UserCooldownEntry {
            user,
            cooldown: UserCooldown {
                cooldown_end,
                underlying_amount: amount,
            },
        };
        vector::push_back(cooldowns, new_entry);
    }
}

fun clear_user_cooldown(user_cooldowns: &mut UserCooldowns, user: address) {
    let cooldowns = &mut user_cooldowns.cooldowns;
    let len = vector::length(cooldowns);
    let mut i = 0;

    while (i < len) {
        let entry = vector::borrow(cooldowns, i);
        if (entry.user == user) {
            vector::remove(cooldowns, i);
            break
        };
        i = i + 1;
    }
}

fun get_user_balance(user_balances: &UserBalances, user: address): u64 {
    let balances = &user_balances.balances;
    let len = vector::length(balances);
    let mut i = 0;

    while (i < len) {
        let entry = vector::borrow(balances, i);
        if (entry.user == user) {
            return entry.balance
        };
        i = i + 1;
    };

    0
}

fun update_user_balance(
    user_balances: &mut UserBalances,
    user: address,
    amount: u64,
    is_increase: bool,
) {
    let balances = &mut user_balances.balances;
    let len = vector::length(balances);
    let mut i = 0;
    let mut found = false;

    while (i < len) {
        let entry = vector::borrow_mut(balances, i);
        if (entry.user == user) {
            if (is_increase) {
                entry.balance = entry.balance + amount;
            } else {
                assert!(entry.balance >= amount, EExcessiveWithdrawAmount);
                entry.balance = entry.balance - amount;
            };
            found = true;
            break
        };
        i = i + 1;
    };

    if (!found && is_increase) {
        let new_entry = UserBalance {
            user,
            balance: amount,
        };
        vector::push_back(balances, new_entry);
    }
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(SDEUSD {}, ctx);
}

#[test_only]
public fun create_management_for_test(ctx: &mut TxContext): StdeUSDManagement {
    let (treasury_cap, deny_cap, metadata) = coin::create_regulated_currency_v2(
        SDEUSD {},
        18,
        b"stdeUSD",
        b"Staked deUSD",
        b"Staked deUSD tokens for earning yield",
        option::none(),
        true,
        ctx
    );
    transfer::public_freeze_object(metadata);

    StdeUSDManagement {
        id: object::new(ctx),
        treasury_cap,
        deny_cap,
        deusd_balance: balance::zero(),
        vesting_amount: 0,
        last_distribution_timestamp: 0,
        cooldown_duration: MAX_COOLDOWN_DURATION,
        total_supply: 0,
        soft_restricted_stakers: set::new(ctx),
        full_restricted_stakers: set::new(ctx),
    }
}

#[test_only]
public fun destroy_management_for_test(management: StdeUSDManagement) {
    let StdeUSDManagement { 
        id, 
        treasury_cap,
        deny_cap,
        deusd_balance, 
        vesting_amount: _, 
        last_distribution_timestamp: _, 
        cooldown_duration: _, 
        total_supply: _, 
        soft_restricted_stakers, 
        full_restricted_stakers 
    } = management;
    id.delete();
    sui::test_utils::destroy(treasury_cap);
    sui::test_utils::destroy(deny_cap);
    deusd_balance.destroy_zero();
    sui::test_utils::destroy(soft_restricted_stakers);
    sui::test_utils::destroy(full_restricted_stakers);
}
