/// This helper contract allows us to distribute the staking rewards without the need of multisig transactions.
/// It increases the distribution frequency and automates almost the whole process, we also mitigate some arbitrage
/// opportunities with this approach.
/// We have two roles:
/// - The owner of this helper will be the multisig (the owner of AdminCap).
/// - The operator will be the delegated signer and is only allowed to mint deUSD using the available funds that land
///   in this contract and calling transferInRewards to send the minted deUSD rewards to the staking contract. The operator
///   can be replaced by the owner at any time with a single transaction.
module elixir::staking_rewards_distributor;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::event;

// === Imports ===

use elixir::deusd::DEUSD;

// === Error codes ===

const EInvalidZeroAddress: u64 = 1;
const ENoAssetsProvided: u64 = 2;
const EOnlyOperator: u64 = 3;
const EInsufficientFunds: u64 = 4;
const EInvalidAmount: u64 = 5;
const ENotOwner: u64 = 6;

// === Structs ===

/// @notice Main contract state for rewards distribution
public struct StakingRewardsDistributor has key {
    id: UID,
    /// @notice admin/owner of the contract
    admin: address,
    /// @notice only address authorized to invoke transfer_in_rewards
    operator: address,
    /// @notice deUSD token balance held by this contract
    deusd_balance: Balance<DEUSD>,
    /// @notice approved assets for minting (tracked as addresses)
    approved_assets: vector<address>,
    /// @notice staking vault address that receives rewards
    staking_vault: address,
}

/// @notice Capability for managing other token balances
public struct TokenBalance<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
}

// === Events ===

public struct RewardsTransferred has copy, drop {
    amount: u64,
    staking_vault: address,
}

public struct TokensRescued has copy, drop {
    token: address,
    to: address,
    amount: u64,
}

public struct OperatorUpdated has copy, drop {
    new_operator: address,
    old_operator: address,
}

public struct AssetsApproved has copy, drop {
    assets: vector<address>,
}

public struct ApprovalsRevoked has copy, drop {
    assets: vector<address>,
    target: address,
}

// === Initialization ===

/// @notice Initialize the StakingRewardsDistributor
fun init(ctx: &mut TxContext) {
    let distributor = StakingRewardsDistributor {
        id: object::new(ctx),
        admin: ctx.sender(),
        operator: @0x0,
        deusd_balance: balance::zero<DEUSD>(),
        approved_assets: vector::empty<address>(),
        staking_vault: @0x0,
    };
    
    transfer::share_object(distributor);
}

// === Public Functions ===

/// @notice Create the distributor with specific parameters
/// @param staking_vault The staking vault address
/// @param assets Initial assets to approve
/// @param admin Admin address
/// @param operator Operator address
public fun create_distributor(
    staking_vault: address,
    assets: vector<address>,
    admin: address,
    operator: address,
    ctx: &mut TxContext
) {
    assert!(staking_vault != @0x0, EInvalidZeroAddress);
    assert!(!vector::is_empty(&assets), ENoAssetsProvided);
    assert!(admin != @0x0, EInvalidZeroAddress);
    assert!(operator != @0x0, EInvalidZeroAddress);
    
    let distributor = StakingRewardsDistributor {
        id: object::new(ctx),
        admin,
        operator,
        deusd_balance: balance::zero<DEUSD>(),
        approved_assets: assets,
        staking_vault,
    };
    
    // Emit events
    event::emit(OperatorUpdated {
        new_operator: operator,
        old_operator: @0x0,
    });
    
    event::emit(AssetsApproved {
        assets,
    });
    
    transfer::share_object(distributor);
}

/// @notice Only the operator can call transfer_in_rewards to transfer deUSD to the staking contract
/// @param distributor The distributor object
/// @param rewards_amount The amount of deUSD to send
/// @dev In order to use this function, we need to set this contract as the REWARDER_ROLE in the staking contract
///      No need to check that the input amount is not 0, since we already check this in the staking contract
public fun transfer_in_rewards(
    distributor: &mut StakingRewardsDistributor,
    rewards_amount: u64,
    ctx: &mut TxContext
): Coin<DEUSD> {
    assert!(ctx.sender() == distributor.operator, EOnlyOperator);
    
    // Check that this contract holds enough deUSD balance to transfer
    assert!(distributor.deusd_balance.value() >= rewards_amount, EInsufficientFunds);
    
    let reward_balance = distributor.deusd_balance.split(rewards_amount);
    let reward_coin = coin::from_balance(reward_balance, ctx);
    
    event::emit(RewardsTransferred {
        amount: rewards_amount,
        staking_vault: distributor.staking_vault,
    });
    
    reward_coin
}

/// @notice Owner can rescue tokens that were accidentally sent to the contract
/// @param distributor The distributor object
/// @param amount The amount of deUSD tokens to rescue
/// @param to The address to send the tokens to
/// @dev only available for the owner
public fun rescue_deusd_tokens(
    distributor: &mut StakingRewardsDistributor,
    amount: u64,
    to: address,
    ctx: &mut TxContext
): Coin<DEUSD> {
    assert!(ctx.sender() == distributor.admin, ENotOwner);
    assert!(to != @0x0, EInvalidZeroAddress);
    assert!(amount > 0, EInvalidAmount);
    
    let rescue_balance = distributor.deusd_balance.split(amount);
    let rescue_coin = coin::from_balance(rescue_balance, ctx);
    
    event::emit(TokensRescued {
        token: @0x0, // Using 0x0 as placeholder for DEUSD type
        to,
        amount,
    });
    
    rescue_coin
}

/// @notice Generic rescue function for other token types
/// @param token_balance The token balance object to rescue from
/// @param amount The amount of tokens to rescue
/// @param to The address to send the tokens to
/// @param distributor The distributor object (for admin check)
/// @dev only available for the owner
public fun rescue_tokens<T>(
    distributor: &StakingRewardsDistributor,
    token_balance: &mut TokenBalance<T>,
    amount: u64,
    to: address,
    ctx: &mut TxContext
): Coin<T> {
    assert!(ctx.sender() == distributor.admin, ENotOwner);
    assert!(to != @0x0, EInvalidZeroAddress);
    assert!(amount > 0, EInvalidAmount);
    
    let rescue_balance = token_balance.balance.split(amount);
    let rescue_coin = coin::from_balance(rescue_balance, ctx);
    
    event::emit(TokensRescued {
        token: @0x0, // Type address placeholder
        to,
        amount,
    });
    
    rescue_coin
}

/// @notice Sets a new operator, removing the previous one
/// @param distributor The distributor object
/// @param new_operator New operator address
/// @dev only available for the owner. We allow the address(0) as a new operator
///      in case that the key is exposed and we just want to remove it
///      as soon as possible being able to set to 0
public fun set_operator(
    distributor: &mut StakingRewardsDistributor,
    new_operator: address,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == distributor.admin, ENotOwner);
    
    let old_operator = distributor.operator;
    distributor.operator = new_operator;
    
    event::emit(OperatorUpdated {
        new_operator,
        old_operator,
    });
}

/// @notice Updates the staking vault address
/// @param distributor The distributor object
/// @param new_staking_vault New staking vault address
public fun set_staking_vault(
    distributor: &mut StakingRewardsDistributor,
    new_staking_vault: address,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == distributor.admin, ENotOwner);
    assert!(new_staking_vault != @0x0, EInvalidZeroAddress);
    
    distributor.staking_vault = new_staking_vault;
}

/// @notice Approves new assets for minting
/// @param distributor The distributor object
/// @param assets Assets to approve
/// @dev only available for the owner
public fun approve_assets(
    distributor: &mut StakingRewardsDistributor,
    assets: vector<address>,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == distributor.admin, ENotOwner);
    assert!(!vector::is_empty(&assets), ENoAssetsProvided);
    
    // Add assets to approved list
    let mut i = 0;
    while (i < vector::length(&assets)) {
        let asset = assets[i];
        if (!vector::contains(&distributor.approved_assets, &asset)) {
            vector::push_back(&mut distributor.approved_assets, asset);
        };
        i = i + 1;
    };
    
    event::emit(AssetsApproved {
        assets,
    });
}

/// @notice Revokes approvals for specified assets
/// @param distributor The distributor object
/// @param assets Assets to revoke
/// @param target Address to revoke the approvals from
/// @dev only available for the owner
public fun revoke_approvals(
    distributor: &mut StakingRewardsDistributor,
    assets: vector<address>,
    target: address,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == distributor.admin, ENotOwner);
    assert!(!vector::is_empty(&assets), ENoAssetsProvided);
    assert!(target != @0x0, EInvalidZeroAddress);
    
    // Remove assets from approved list if target is self
    if (target == object::uid_to_address(&distributor.id)) {
        let mut i = 0;
        while (i < vector::length(&assets)) {
            let asset = assets[i];
            let (found, index) = vector::index_of(&distributor.approved_assets, &asset);
            if (found) {
                vector::remove(&mut distributor.approved_assets, index);
            };
            i = i + 1;
        };
    };
    
    event::emit(ApprovalsRevoked {
        assets,
        target,
    });
}

/// @notice Transfer admin role to a new address
/// @param distributor The distributor object
/// @param new_admin New admin address
public fun transfer_admin(
    distributor: &mut StakingRewardsDistributor,
    new_admin: address,
    ctx: &mut TxContext
) {
    assert!(ctx.sender() == distributor.admin, ENotOwner);
    assert!(new_admin != @0x0, EInvalidZeroAddress);
    
    distributor.admin = new_admin;
}

// === Helper Functions ===

/// @notice Add deUSD balance to the distributor
/// @param distributor The distributor object
/// @param deusd_coin The deUSD coin to add
public fun add_deusd_balance(
    distributor: &mut StakingRewardsDistributor,
    deusd_coin: Coin<DEUSD>
) {
    let added_balance = coin::into_balance(deusd_coin);
    distributor.deusd_balance.join(added_balance);
}

/// @notice Create a token balance object for managing other tokens
/// @param ctx Transaction context
public fun create_token_balance<T>(ctx: &mut TxContext): TokenBalance<T> {
    TokenBalance {
        id: object::new(ctx),
        balance: balance::zero<T>(),
    }
}

/// @notice Add balance to a token balance object
/// @param token_balance The token balance object
/// @param coin The coin to add
public fun add_token_balance<T>(
    token_balance: &mut TokenBalance<T>,
    coin: Coin<T>
) {
    let added_balance = coin::into_balance(coin);
    token_balance.balance.join(added_balance);
}

// === View Functions ===

/// @notice Get the current admin address
public fun get_admin(distributor: &StakingRewardsDistributor): address {
    distributor.admin
}

/// @notice Get the current operator address
public fun get_operator(distributor: &StakingRewardsDistributor): address {
    distributor.operator
}

/// @notice Get the staking vault address
public fun get_staking_vault(distributor: &StakingRewardsDistributor): address {
    distributor.staking_vault
}

/// @notice Get the deUSD balance
public fun get_deusd_balance(distributor: &StakingRewardsDistributor): u64 {
    distributor.deusd_balance.value()
}

/// @notice Get the approved assets
public fun get_approved_assets(distributor: &StakingRewardsDistributor): &vector<address> {
    &distributor.approved_assets
}

/// @notice Get token balance value
public fun get_token_balance<T>(token_balance: &TokenBalance<T>): u64 {
    token_balance.balance.value()
}

/// @notice Get the distributor object ID address
public fun get_distributor_id(distributor: &StakingRewardsDistributor): address {
    object::uid_to_address(&distributor.id)
}

// === Test-only Functions ===

#[test_only]
/// @notice Initialize the module for testing
public fun init_for_test(ctx: &mut TxContext) {
    init(ctx);
}
