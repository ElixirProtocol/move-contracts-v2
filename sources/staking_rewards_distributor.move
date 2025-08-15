/// This helper contract allows us to distribute the staking rewards without the need of multisig transactions.
/// It increases the distribution frequency and automates almost the whole process, we also mitigate some arbitrage
/// opportunities with this approach.
/// We have two roles:
/// - The owner of this helper will be the multisig (the owner of AdminCap).
/// - The operator will be the delegated signer and is only allowed to mint deUSD using the available funds that land
///   in this contract and calling transfer_in_rewards to send the minted deUSD rewards to the staking contract. The operator
///   can be replaced by the owner at any time with a single transaction.
module elixir::staking_rewards_distributor;

use elixir::config::GlobalConfig;
use elixir::sdeusd::SdeUSDManagement;
use elixir::sdeusd;
use elixir::admin_cap::AdminCap;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::event;

// === Imports ===

use elixir::deusd::DEUSD;

// === Error codes ===

const EOnlyOperator: u64 = 3;
const EInsufficientFunds: u64 = 4;
const EInvalidAmount: u64 = 5;

// === Structs ===

/// Main contract state for rewards distribution
public struct StakingRewardsDistributor has key {
    id: UID,
    /// Only address authorized to invoke transfer_in_rewards
    operator: address,
    /// deUSD token balance held by this contract
    deusd_balance: Balance<DEUSD>,
}

// === Events ===

public struct RewardsTransferred has copy, drop {
    amount: u64,
}

public struct OperatorUpdated has copy, drop {
    new_operator: address,
    old_operator: address,
}

public struct DeUSDDeposited has copy, drop {
    sender: address,
    amount: u64,
}

public struct DeUSDWithdrawn has copy, drop {
    amount: u64,
    to: address,
}

// === Initialization ===

/// @notice Initialize the StakingRewardsDistributor
fun init(ctx: &mut TxContext) {
    let distributor = StakingRewardsDistributor {
        id: object::new(ctx),
        operator: @0x0,
        deusd_balance: balance::zero<DEUSD>(),
    };
    
    transfer::share_object(distributor);
}

// === Public Functions ===

/// Only the operator can call transfer_in_rewards to transfer deUSD to the staking contract
/// @param distributor The distributor object
/// @param rewards_amount The amount of deUSD to send
/// @dev In order to use this function, we need to set operator as the REWARDER_ROLE in the staking contract
///      No need to check that the input amount is not 0, since we already check this in the staking contract
public fun transfer_in_rewards(
    distributor: &mut StakingRewardsDistributor,
    sdeusd_management: &mut SdeUSDManagement,
    global_config: &GlobalConfig,
    rewards_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    global_config.check_package_version();

    assert!(ctx.sender() == distributor.operator, EOnlyOperator);
    
    // Check that this contract holds enough deUSD balance to transfer
    assert!(distributor.deusd_balance.value() >= rewards_amount, EInsufficientFunds);
    
    let reward_balance = distributor.deusd_balance.split(rewards_amount);
    let reward_coin = coin::from_balance(reward_balance, ctx);

    sdeusd::transfer_in_rewards(sdeusd_management, global_config, reward_coin, clock, ctx);
    
    event::emit(RewardsTransferred {
        amount: rewards_amount,
    });
}

/// Sets a new operator, removing the previous one
/// @param distributor The distributor object
/// @param new_operator New operator address
/// @dev only available for the owner. We allow the address(@0x0) as a new operator
///      in case that the key is exposed and we just want to remove it
///      as soon as possible being able to set to @0x0
public fun set_operator(
    _: &AdminCap,
    distributor: &mut StakingRewardsDistributor,
    global_config: &GlobalConfig,
    new_operator: address,
    _ctx: &mut TxContext
) {
    global_config.check_package_version();

    let old_operator = distributor.operator;
    distributor.operator = new_operator;
    
    event::emit(OperatorUpdated {
        new_operator,
        old_operator,
    });
}

/// Deposit deUSD balance to the distributor
/// @param distributor The distributor object
/// @param deusd_coin The deUSD coin to add
public fun deposit_deusd(
    distributor: &mut StakingRewardsDistributor,
    global_config: &GlobalConfig,
    deusd_coin: Coin<DEUSD>,
    ctx: &TxContext,
) {
    global_config.check_package_version();

    let amount = deusd_coin.value();
    distributor.deusd_balance.join(coin::into_balance(deusd_coin));

    event::emit(DeUSDDeposited {
        sender: ctx.sender(),
        amount,
    });
}

/// Withdraw deUSD balance from the distributor. Only the admin can call this function.
public fun withdraw_deusd(
    _: &AdminCap,
    distributor: &mut StakingRewardsDistributor,
    global_config: &GlobalConfig,
    amount: u64,
    to: address,
    ctx: &mut TxContext,
) {
    global_config.check_package_version();

    assert!(amount > 0, EInvalidAmount);

    let withdrawn_balance = distributor.deusd_balance.split(amount);
    let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);

    transfer::public_transfer(withdrawn_coin, to);

    event::emit(DeUSDWithdrawn {
        amount,
        to,
    });
}

// === View Functions ===

/// Get the current operator address
public fun get_operator(distributor: &StakingRewardsDistributor): address {
    distributor.operator
}

/// @notice Get the deUSD balance
public fun get_deusd_balance(distributor: &StakingRewardsDistributor): u64 {
    distributor.deusd_balance.value()
}

// === Test-only Functions ===

#[test_only]
/// @notice Initialize the module for testing
public fun init_for_test(ctx: &mut TxContext) {
    init(ctx);
}
