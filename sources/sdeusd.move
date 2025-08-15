/// The stdeUSD contract allows users to stake deUSD tokens and earn a portion of protocol LST and
/// perpetual yield that is allocated to stakers by the Elixir Foundation voted yield distribution algorithm.
/// The algorithm seeks to balance the stability of the protocol by funding
/// the protocol's insurance fund, DAO activities, and rewarding stakers with a portion of the protocol's yield.
#[allow(unused_const)]
module elixir::sdeusd;

// === Imports ===

use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin, TreasuryCap, DenyCapV2};
use sui::balance::{Self, Balance};
use sui::deny_list::DenyList;
use sui::event;
use sui::table::{Self, Table};
use elixir::set::{Self, Set};
use elixir::config::GlobalConfig;
use elixir::admin_cap::AdminCap;
use elixir::deusd::DEUSD;
use elixir::math_u64;
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

/// Main management struct for the staked deUSD contract
public struct SdeUSDManagement has key {
    id: UID,
    /// Treasury cap for minting/burning stdeUSD tokens
    treasury_cap: TreasuryCap<SDEUSD>,
    /// Deny cap for stdeUSD tokens
    deny_cap: DenyCapV2<SDEUSD>,
    /// Balance of deUSD tokens held by the contract
    deusd_balance: Balance<DEUSD>,
    /// Balance of deUSD tokens held in the silo for unstaking
    silo_balance: Balance<DEUSD>,
    /// The amount of the last asset distribution
    vesting_amount: u64,
    /// The timestamp of the last asset distribution
    last_distribution_timestamp: u64,
    /// Current cooldown time period
    cooldown_duration: u64,
    /// Mapping of address to it's cooldown time
    cooldowns: Table<address, UserCooldown>,
    /// Soft restricted stakers (cannot stake)
    soft_restricted_stakers: Set<address>,
    /// Full restricted stakers (cannot transfer, stake, or unstake)
    full_restricted_stakers: Set<address>,
}

/// User cooldown information
public struct UserCooldown has store {
    cooldown_end: u64,
    underlying_amount: u64,
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
    sender: address,
    receiver: address,
    assets: u64,
    shares: u64,
}

public struct Withdraw has copy, drop, store {
    sender: address,
    receiver: address,
    owner: address,
    assets: u64,
    shares: u64,
}

public struct WithdrawToSilo has copy, drop, store {
    sender: address,
    assets: u64,
    shares: u64,
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

    let management = SdeUSDManagement {
        id: object::new(ctx),
        treasury_cap,
        deny_cap,
        deusd_balance: balance::zero(),
        silo_balance: balance::zero(),
        vesting_amount: 0,
        last_distribution_timestamp: 0,
        cooldown_duration: MAX_COOLDOWN_DURATION,
        cooldowns: table::new(ctx),
        soft_restricted_stakers: set::new(ctx),
        full_restricted_stakers: set::new(ctx),
    };
    transfer::share_object(management);
}

// === Public Functions ===

/// Allows a rewarder to transfer deUSD rewards into the contract and updates vesting state.
public fun transfer_in_rewards(
    management: &mut SdeUSDManagement,
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
    management: &mut SdeUSDManagement,
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
    management: &mut SdeUSDManagement,
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

/// Withdraws deUSD assets by burning stdeUSD shares. The shares are split from the provided coin.
public fun withdraw(
    management: &mut SdeUSDManagement,
    global_config: &GlobalConfig,
    assets: u64,
    shares_coin: &mut Coin<SDEUSD>,
    receiver: address,
    owner: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert_cooldown_off(management);

    let shares = preview_withdraw(management, assets, clock);
    let shares_coin_to_use = shares_coin.split(shares, ctx);

    withdraw_to_user(
        management, 
        ctx.sender(),
        receiver, 
        owner, 
        assets, 
        shares_coin_to_use,
        ctx
    );

    // if (shares_coin.value() != 0) {
    //     transfer::public_transfer(shares_coin, receiver);
    // } else {
    //     coin::destroy_zero(shares_coin);
    // };
}

/// Deposits deUSD and mints sdeUSD shares to the receiver. Fails if sender or receiver is soft restricted.
public fun deposit(
    management: &mut SdeUSDManagement,
    global_config: &GlobalConfig,
    assets_coin: Coin<DEUSD>,
    receiver: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();

    let sender = ctx.sender();
    assert!(!is_soft_restricted_staker(management, sender), EOperationNotAllowed);
    assert!(!is_soft_restricted_staker(management, receiver), EOperationNotAllowed);

    let assets = assets_coin.value();
    assert!(assets > 0, EZeroAmount);

    let shares = preview_deposit(management, assets, clock);
    assert!(shares > 0, EZeroAmount);

    management.deusd_balance.join(coin::into_balance(assets_coin));

    let shares_coin = coin::mint(&mut management.treasury_cap, shares, ctx);
    transfer::public_transfer(shares_coin, receiver);

    check_min_shares(management);

    event::emit(Deposit {
        sender,
        receiver,
        assets,
        shares,
    });
}

/// Mints sdeUSD shares for the specified amount.
/// The remaining deUSD coins will be returned to the sender.
public fun mint(
    management: &mut SdeUSDManagement,
    global_config: &GlobalConfig,
    assets_coin: &mut Coin<DEUSD>,
    shares: u64,
    receiver: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert!(assets_coin.value() > 0, EZeroAmount);

    let sender = ctx.sender();
    assert!(!is_soft_restricted_staker(management, sender), EOperationNotAllowed);
    assert!(!is_soft_restricted_staker(management, receiver), EOperationNotAllowed);

    let assets = preview_mint(management, shares, clock);
    assert!(assets > 0, EZeroAmount);

    let assets_coin_to_mint = assets_coin.split(assets, ctx);
    management.deusd_balance.join(coin::into_balance(assets_coin_to_mint));

    let shares_coin = coin::mint(&mut management.treasury_cap, shares, ctx);
    transfer::public_transfer(shares_coin, receiver);

    check_min_shares(management);

    event::emit(Deposit {
        sender,
        receiver,
        assets,
        shares,
    });
}

/// Redeems stdeUSD shares for deUSD assets. The shares are burned and assets are sent to the receiver.
public fun redeem(
    management: &mut SdeUSDManagement,
    global_config: &GlobalConfig,
    shares_coin: Coin<SDEUSD>,
    receiver: address,
    owner: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert_cooldown_off(management);

    let shares = shares_coin.value();
    let assets = preview_redeem(management, shares, clock);

    withdraw_to_user(
        management, 
        ctx.sender(),
        receiver, 
        owner, 
        assets, 
        shares_coin,
        ctx
    );
}

/// Starts a cooldown for withdrawal by burning shares for deUSD, which is held in the silo until cooldown ends.
public fun cooldown_assets(
    management: &mut SdeUSDManagement,
    global_config: &GlobalConfig,
    assets: u64,
    shares_coin: &mut Coin<SDEUSD>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert_cooldown_on(management);

    let sender = ctx.sender();
    let max_shares = shares_coin.value();
    assert!(assets <= max_withdraw(management, max_shares, clock), EExcessiveWithdrawAmount);

    let shares = preview_withdraw(management, assets, clock);

    update_user_cooldown(management, sender, assets, clock);

    withdraw_to_silo(
        management,
        sender,
        assets,
        shares_coin.split(shares, ctx),
        ctx,
    );
}

/// Starts a cooldown by burning a specific amount of shares
public fun cooldown_shares(
    management: &mut SdeUSDManagement,
    global_config: &GlobalConfig,
    shares_coin: &mut Coin<SDEUSD>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    assert!(management.cooldown_duration > 0, EOperationNotAllowed);

    let sender = ctx.sender();

    let shares = shares_coin.value();
    let assets = preview_redeem(management, shares, clock);

    update_user_cooldown(management, sender, assets, clock);

    withdraw_to_silo(
        management,
        sender,
        assets,
        shares_coin.split(shares, ctx),
        ctx,
    );
}

/// Claims unstaked deUSD from the silo after cooldown period has ended.
public fun unstake(
    management: &mut SdeUSDManagement,
    global_config: &GlobalConfig,
    receiver: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();
    
    let sender = ctx.sender();

    assert!(management.cooldowns.contains(sender), EOperationNotAllowed);

    let cooldown = management.cooldowns.borrow_mut(sender);

    let current_time = clock::timestamp_ms(clock);
    assert!(
        current_time >= cooldown.cooldown_end || management.cooldown_duration == 0,
        EInvalidCooldown
    );

    let assets = cooldown.underlying_amount;

    cooldown.cooldown_end = 0;
    cooldown.underlying_amount = 0;

    let assets_coin = coin::from_balance(management.silo_balance.split(assets), ctx);
    transfer::public_transfer(assets_coin, receiver);

    event::emit(Unstaked {
        user: sender,
        receiver,
        assets,
    });
}

/// Sets the cooldown duration for withdrawals. Only callable by admin.
public fun set_cooldown_duration(
    _: &AdminCap,
    management: &mut SdeUSDManagement,
    global_config: &GlobalConfig,
    duration: u64,
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

/// Returns the amount of deUSD tokens that are vested in the contract.
public fun total_assets(management: &SdeUSDManagement, clock: &Clock): u64 {
    let total_balance = management.deusd_balance.value();
    let unvested = get_unvested_amount(management, clock);
    if (total_balance >= unvested) {
        total_balance - unvested
    } else {
        0
    }
}

/// Returns the amount of deUSD tokens that are unvested in the contract.
public fun get_unvested_amount(management: &SdeUSDManagement, clock: &Clock): u64 {
    let current_time = clock::timestamp_ms(clock);
    let time_since_last_distribution = current_time - management.last_distribution_timestamp;

    if (time_since_last_distribution >= VESTING_PERIOD) {
        return 0
    };

    math_u64::mul_div(VESTING_PERIOD - time_since_last_distribution, management.vesting_amount, VESTING_PERIOD, false)
}

/// Calculates the number of stdeUSD shares to mint for a given deposit amount.
public fun preview_deposit(management: &mut SdeUSDManagement, assets: u64, clock: &Clock): u64 {
    let total_supply = total_supply(management);
    if (total_supply == 0) {
        assets
    } else {
        let total_assets = total_assets(management, clock);
        if (total_assets == 0) {
            assets
        } else {
            math_u64::mul_div(assets, total_supply, total_assets, false)
        }
    }
}

/// Calculates the amount of assets required to mint a specific number of shares
public fun preview_mint(management: &mut SdeUSDManagement, shares: u64, clock: &Clock): u64 {
    let total_supply = total_supply(management);
    if (total_supply == 0) {
        shares
    } else {
        let total_assets = total_assets(management, clock);
        math_u64::mul_div(shares, total_assets, total_supply, true)
    }
}

/// Calculates the amount of deUSD to return for a given number of stdeUSD shares.
public fun preview_redeem(management: &mut SdeUSDManagement, shares: u64, clock: &Clock): u64 {
    let total_supply = total_supply(management);
    if (total_supply == 0) {
        0
    } else {
        let total_assets = total_assets(management, clock);
        math_u64::mul_div(shares, total_assets, total_supply, false)
    }
}

/// Calculates the number of shares to burn for a specific amount of assets
public fun preview_withdraw(management: &mut SdeUSDManagement, assets: u64, clock: &Clock): u64 {
    let total_supply = total_supply(management);
    if (total_supply == 0) {
        assets
    } else {
        let total_assets = total_assets(management, clock);
        if (total_assets == 0) {
            assets
        } else {
            math_u64::mul_div(assets, total_supply, total_assets, true)
        }
    }
}

/// Returns the maximum amount of deUSD a user can withdraw.
public fun max_withdraw(
    management: &mut SdeUSDManagement,
    user_balance: u64,
    clock: &Clock
): u64 {
    preview_redeem(management, user_balance, clock)
}

/// Get user's current cooldown information
public fun get_user_cooldown_info(management: &SdeUSDManagement, user: address): (u64, u64) {
    if (management.cooldowns.contains(user)) {
        let cooldown = management.cooldowns.borrow(user);
        (cooldown.cooldown_end, cooldown.underlying_amount)
    } else {
        (0, 0)
    }
}

/// Get the underlying amount from a cooldown
public fun cooldown_underlying_amount(cooldown: &UserCooldown): u64 {
    cooldown.underlying_amount
}

/// Get the cooldown end time
public fun cooldown_end_time(cooldown: &UserCooldown): u64 {
    cooldown.cooldown_end
}

/// Get total supply of stdeUSD
public fun total_supply(management: &mut SdeUSDManagement): u64 {
    management.treasury_cap.supply().supply_value()
}

/// Get current cooldown duration
public fun cooldown_duration(management: &SdeUSDManagement): u64 {
    management.cooldown_duration
}

/// Check if a user is soft restricted
public fun is_soft_restricted(management: &SdeUSDManagement, user: address): bool {
    is_soft_restricted_staker(management, user)
}

/// Check if a user is full restricted
public fun is_full_restricted(management: &SdeUSDManagement, user: address): bool {
    is_full_restricted_staker(management, user)
}

// === Helper Functions ===

fun is_soft_restricted_staker(management: &SdeUSDManagement, user: address): bool {
    management.soft_restricted_stakers.contains(user)
}

fun is_full_restricted_staker(management: &SdeUSDManagement, user: address): bool {
    management.full_restricted_stakers.contains(user)
}

fun update_vesting_amount(management: &mut SdeUSDManagement, new_vesting_amount: u64, clock: &Clock) {
    assert!(get_unvested_amount(management, clock) == 0, EStillVesting);

    management.vesting_amount = new_vesting_amount;
    management.last_distribution_timestamp = clock::timestamp_ms(clock);
}

fun check_min_shares(management: &mut SdeUSDManagement) {
    let total_supply = total_supply(management);
    assert!(total_supply == 0 || total_supply >= MIN_SHARES, EMinSharesViolation);
}

fun assert_cooldown_on(management: &SdeUSDManagement) {
    assert!(management.cooldown_duration != 0, EOperationNotAllowed);
}

fun assert_cooldown_off(management: &SdeUSDManagement) {
    assert!(management.cooldown_duration == 0, EOperationNotAllowed);
}

fun withdraw_to_user(
    management: &mut SdeUSDManagement,
    sender: address,
    receiver: address,
    owner: address,
    assets: u64,
    shares_coin: Coin<SDEUSD>,
    ctx: &mut TxContext,
) {
    assert!(assets > 0, EZeroAmount);

    let shares = shares_coin.value();
    assert!(shares > 0, EZeroAmount);

    // Check restrictions
    assert!(!is_full_restricted_staker(management, sender), EOperationNotAllowed);
    assert!(!is_full_restricted_staker(management, receiver), EOperationNotAllowed);
    assert!(!is_full_restricted_staker(management, owner), EOperationNotAllowed);

    coin::burn(&mut management.treasury_cap, shares_coin);
    let assets_coin = coin::from_balance(management.deusd_balance.split(assets), ctx);
    transfer::public_transfer(assets_coin, owner);

    check_min_shares(management);

    event::emit(Withdraw {
        sender,
        receiver,
        owner,
        assets,
        shares,
    });
}

fun withdraw_to_silo(
    management: &mut SdeUSDManagement,
    sender: address,
    assets: u64,
    shares_coin: Coin<SDEUSD>,
    ctx: &mut TxContext,
) {
    assert!(assets > 0, EZeroAmount);

    let shares = shares_coin.value();
    assert!(shares > 0, EZeroAmount);

    // Check restrictions
    assert!(!is_full_restricted_staker(management, sender), EOperationNotAllowed);

    coin::burn(&mut management.treasury_cap, shares_coin);
    let assets_coin = coin::from_balance(management.deusd_balance.split(assets), ctx);
    management.silo_balance.join(coin::into_balance(assets_coin));

    check_min_shares(management);

    event::emit(WithdrawToSilo {
        sender,
        assets,
        shares,
    });
}

fun update_user_cooldown(
    management: &mut SdeUSDManagement,
    user: address,
    amount: u64,
    clock: &Clock,
) {
    if (management.cooldowns.contains(user)) {
        let cooldown = management.cooldowns.borrow_mut(user);
        cooldown.cooldown_end = clock::timestamp_ms(clock) + management.cooldown_duration;
        cooldown.underlying_amount = cooldown.underlying_amount + amount;
    } else {
        management.cooldowns.add(user, UserCooldown {
            cooldown_end: clock::timestamp_ms(clock) + management.cooldown_duration,
            underlying_amount: amount,
        })
    };
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(SDEUSD {}, ctx);
}

#[test_only]
public fun create_management_for_test(ctx: &mut TxContext): SdeUSDManagement {
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

    SdeUSDManagement {
        id: object::new(ctx),
        treasury_cap,
        deny_cap,
        deusd_balance: balance::zero(),
        silo_balance: balance::zero(),
        vesting_amount: 0,
        last_distribution_timestamp: 0,
        cooldown_duration: MAX_COOLDOWN_DURATION,
        cooldowns: table::new(ctx),
        soft_restricted_stakers: set::new(ctx),
        full_restricted_stakers: set::new(ctx),
    }
}

#[test_only]
public fun destroy_management_for_test(management: SdeUSDManagement) {
    let SdeUSDManagement {
        id, 
        treasury_cap,
        deny_cap,
        deusd_balance,
        silo_balance,
        vesting_amount: _, 
        last_distribution_timestamp: _, 
        cooldown_duration: _,
        cooldowns,
        soft_restricted_stakers,
        full_restricted_stakers 
    } = management;
    id.delete();
    sui::test_utils::destroy(treasury_cap);
    sui::test_utils::destroy(deny_cap);
    deusd_balance.destroy_for_testing();
    silo_balance.destroy_for_testing();
    sui::test_utils::destroy(cooldowns);
    sui::test_utils::destroy(soft_restricted_stakers);
    sui::test_utils::destroy(full_restricted_stakers);
}
