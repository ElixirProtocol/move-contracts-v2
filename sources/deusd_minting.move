module elixir::deusd_minting;

// === Imports ===

use std::ascii;
use std::ascii::String;
use std::type_name;
use std::type_name::TypeName;
use sui::balance;
use sui::balance::Balance;
use sui::bcs;
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::dynamic_field::{Self as df};
use sui::ed25519;
use sui::event;
use sui::hash;
use sui::table::{Self, Table};
use elixir::admin_cap::AdminCap;
use elixir::clock_utils;
use elixir::config::{Self, GlobalConfig};
use elixir::cryptography;
use elixir::deusd::{Self, DEUSD, DeUSDConfig};
use elixir::math_u64;
use elixir::roles;
use elixir::set::{Self, Set};

// === Error codes ===

/// The module is initialized, could not be initialized again.
const EInitialized: u64 = 0;
/// The module is not initialized.
const ENotInitialized: u64 = 1;
/// Invalid route.
const EInvalidRoute: u64 = 2;
/// Max mint per block exceeded.
const EMaxMintPerBlockExceeded: u64 = 3;
/// Max redeem per block exceeded.
const EMaxRedeemPerBlockExceeded: u64 = 4;
/// Invalid address.
const EInvalidAddress: u64 = 5;
/// Invalid amount.
const EInvalidAmount: u64 = 6;
/// Signature expired.
const ESignatureExpired: u64 = 7;
/// Unsupported asset.
const EUnsupportedAsset: u64 = 8;
/// Invalid custodian address.
const EInvalidCustodianAddress: u64 = 9;
/// Invalid nonce.
const EInvalidNonce: u64 = 10;
/// Delegation not initiated.
const EDelegationNotInitiated: u64 = 11;
/// Not authorized.
const ENotAuthorized: u64 = 12;
/// Invalid signature.
const EInvalidSignature: u64 = 13;

// === Constants ===

const ORDER_TYPE_MINT: u8 = 0;
const ORDER_TYPE_REDEEM: u8 = 1;

/// Required ratio for route (10000 = 100%)
const ROUTE_REQUIRED_RATIO: u64 = 10_000;

const DELEGATED_SIGNER_STATUS_NO_STATUS: u8 = 0;
const DELEGATED_SIGNER_STATUS_PENDING: u8 = 1;
const DELEGATED_SIGNER_STATUS_ACCEPTED: u8 = 2;
const DELEGATED_SIGNER_STATUS_REJECTED: u8 = 3;

// === Structs ===

public struct DeUSDMintingManagement has key {
    id: UID,
    address: address,
    /// Supported assets for collateral
    supported_assets: Set<TypeName>,
    /// Custodian addresses
    custodian_addresses: Set<address>,
    /// Order nonce tracking per user
    order_bitmaps: Table<address, Table<u64, u256>>,
    /// deUSD minted per second
    minted_per_second: Table<u64, u64>,
    /// deUSD redeemed per second
    redeemed_per_second: Table<u64, u64>,
    /// Delegated signers mapping
    delegated_signers: Table<address, Table<address, u8>>,
    /// Max mint per second
    max_mint_per_second: u64,
    /// Max redeem per second
    max_redeem_per_second: u64,
    initialized: bool,
}

public struct BalanceStoreKey<phantom T> has copy, drop, store {}

// === Events ===

public struct Mint has copy, drop, store {
    minter: address,
    benefactor: address,
    beneficiary: address,
    collateral_asset: String,
    collateral_amount: u64,
    deusd_amount: u64,
}

public struct Redeem has copy, drop, store {
    redeemer: address,
    benefactor: address,
    beneficiary: address,
    collateral_asset: String,
    collateral_amount: u64,
    deusd_amount: u64,
}

public struct AssetAdded has copy, drop, store {
    asset: TypeName,
}

public struct AssetRemoved has copy, drop, store {
    asset: TypeName,
}

public struct CustodianAddressAdded has copy, drop, store {
    custodian: address,
}

public struct CustodianAddressRemoved has copy, drop, store {
    custodian: address,
}

public struct MaxMintPerSecondChanged has copy, drop, store {
    old_max: u64,
    new_max: u64,
}

public struct MaxRedeemPerBlockChanged has copy, drop, store {
    old_max: u64,
    new_max: u64,
}

public struct DelegatedSignerInitiated has copy, drop, store {
    signer: address,
    delegator: address,
}

public struct DelegatedSignerAdded has copy, drop, store {
    signer: address,
    delegator: address,
}

public struct DelegatedSignerRemoved has copy, drop, store {
    signer: address,
    delegator: address,
}

public struct CustodyTransfer has copy, drop, store {
    wallet: address,
    asset: TypeName,
    amount: u64,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    let management = DeUSDMintingManagement {
        id: object::new(ctx),
        address: @elixir,
        supported_assets: set::new(ctx),
        custodian_addresses: set::new(ctx),
        order_bitmaps: table::new(ctx),
        minted_per_second: table::new(ctx),
        redeemed_per_second: table::new(ctx),
        delegated_signers: table::new(ctx),
        max_mint_per_second: 0,
        max_redeem_per_second: 0,
        initialized: false,
    };
    transfer::share_object(management);
}

// === Public Functions ===

/// Initialize the deUSD minting contract
public fun initialize(
    _: &AdminCap,
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    custodians: vector<address>,
    max_mint_per_second: u64,
    max_redeem_per_second: u64,
) {
    global_config.check_package_version();
    assert!(!management.initialized, EInitialized);

    management.initialized = true;

    let mut j = 0;
    let custodians_length = vector::length(&custodians);
    while (j < custodians_length) {
        add_custodian_address_internal(management, custodians[j]);
        j = j + 1;
    };

    set_max_mint_per_second_internal(management, max_mint_per_second);
    set_max_redeem_per_second_internal(management, max_redeem_per_second);
}

/// Mint deUSDs from assets
public fun mint<T>(
    management: &mut DeUSDMintingManagement,
    deusd_management: &mut DeUSDConfig,
    global_config: &GlobalConfig,
    expiry: u64,
    nonce: u64,
    benefactor: address,
    beneficiary: address,
    collateral: Coin<T>,
    deusd_amount: u64,
    // Route parameters
    route_addresses: vector<address>,
    route_ratios: vector<u64>,
    public_key: vector<u8>,
    signature: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_package_version_and_initialized(management, global_config);

    assert_is_minter(global_config, ctx);

    let collateral_amount = collateral.value();

    verify_order<T>(
        management,
        ORDER_TYPE_MINT,
        expiry,
        nonce,
        benefactor,
        beneficiary,
        collateral_amount,
        deusd_amount,
        public_key,
        signature,
        clock,
    );
    assert!(verify_route(route_addresses, route_ratios, &management.custodian_addresses), EInvalidRoute);

    let now_seconds = clock_utils::timestamp_seconds(clock);

    let current_minted = get_minted_per_second(management, now_seconds);
    assert!(current_minted + deusd_amount <= management.max_mint_per_second, EMaxMintPerBlockExceeded);

    deduplicate_order(management, benefactor, nonce, ctx);

    // Update minted amount for this second
    update_minted_per_second(management, now_seconds, deusd_amount);

    transfer_collateral(management, collateral, benefactor, route_addresses, route_ratios, ctx);

    deusd::mint(deusd_management, beneficiary, deusd_amount, global_config, ctx);

    event::emit(Mint {
        minter: ctx.sender(),
        benefactor,
        beneficiary,
        collateral_asset: type_name::get<T>().into_string(),
        collateral_amount,
        deusd_amount,
    });
}

/// Redeem deUSD for collateral assets with individual order parameters
public fun redeem<T>(
    management: &mut DeUSDMintingManagement,
    deusd_config: &mut DeUSDConfig,
    global_config: &GlobalConfig,
    // Order parameters
    expiry: u64,
    nonce: u64,
    benefactor: address,
    beneficiary: address,
    collateral_amount: u64,
    deusd_coins: Coin<DEUSD>,
    public_key: vector<u8>,
    signature: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_package_version_and_initialized(management, global_config);

    assert_is_redeemer(global_config, ctx);

    let deusd_amount = deusd_coins.value();

    verify_order<T>(
        management,
        ORDER_TYPE_REDEEM,
        expiry,
        nonce,
        benefactor,
        beneficiary,
        collateral_amount,
        deusd_amount,
        public_key,
        signature,
        clock,
    );

    let now_seconds = clock_utils::timestamp_seconds(clock);

    let current_redeemed = get_redeemed_per_second(management, now_seconds);
    assert!(current_redeemed + deusd_amount <= management.max_redeem_per_second, EMaxRedeemPerBlockExceeded);

    deduplicate_order(management, benefactor, nonce, ctx);

    update_redeemed_per_second(management, now_seconds, deusd_amount);

    deusd::burn(deusd_config, deusd_coins, global_config, ctx);

    transfer_to_beneficiary<T>(management, beneficiary, collateral_amount, ctx);

    event::emit(Redeem {
        redeemer: ctx.sender(),
        benefactor,
        beneficiary,
        collateral_asset: type_name::get<T>().into_string(),
        collateral_amount,
        deusd_amount,
    });
}

/// Add supported asset
public fun add_supported_asset<T>(
    _: &AdminCap,
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
) {
    assert_package_version_and_initialized(management, global_config);

    let asset = type_name::get<T>();
    management.supported_assets.add(asset);

    event::emit(AssetAdded { asset });
}

/// Remove supported asset
public fun remove_supported_asset<T>(
    _: &AdminCap,
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
) {
    assert_package_version_and_initialized(management, global_config);

    let asset = type_name::get<T>();
    management.supported_assets.remove(asset);

    event::emit(AssetRemoved { asset });
}

/// Add custodian address
public fun add_custodian_address(
    _: &AdminCap,
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    custodian: address,
) {
    assert_package_version_and_initialized(management, global_config);

    add_custodian_address_internal(management, custodian);
}

/// Remove custodian address
public fun remove_custodian_address(
    _: &AdminCap,
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    custodian: address,
) {
    assert_package_version_and_initialized(management, global_config);

    management.custodian_addresses.remove(custodian);

    event::emit(CustodianAddressRemoved { custodian });
}

/// Set max mint per second
public fun set_max_mint_per_second(
    _: &AdminCap,
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    max_mint: u64,
) {
    assert_package_version_and_initialized(management, global_config);

    set_max_mint_per_second_internal(management, max_mint);
}

/// Set max redeem per second
public fun set_max_redeem_per_second(
    _: &AdminCap,
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    max_redeem: u64,
) {
    assert_package_version_and_initialized(management, global_config);

    set_max_redeem_per_second_internal(management, max_redeem);
}

/// Disable mint and redeem (emergency function)
public fun disable_mint_redeem(
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    ctx: &TxContext,
) {
    assert_package_version_and_initialized(management, global_config);
    assert_is_gatekeeper(global_config, ctx);

    management.max_mint_per_second = 0;
    management.max_redeem_per_second = 0;
}

/// Removes the minter role from an account, can ONLY be executed by the gatekeeper role
public fun remove_minter_role(
    management: &mut DeUSDMintingManagement,
    global_config: &mut GlobalConfig,
    minter: address,
    ctx: &TxContext,
) {
    assert_package_version_and_initialized(management, global_config);
    assert_is_gatekeeper(global_config, ctx);

    config::remove_role_internal(global_config, minter, roles::role_minter());
}

/// Removes the redeemer role from an account, can ONLY be executed by the gatekeeper role
public fun remove_redeemer_role(
    management: &mut DeUSDMintingManagement,
    global_config: &mut GlobalConfig,
    redeemer: address,
    ctx: &TxContext,
) {
    assert_package_version_and_initialized(management, global_config);
    assert_is_gatekeeper(global_config, ctx);

    config::remove_role_internal(global_config, redeemer, roles::role_redeemer());
}

/// Removes the collateral manager role from an account, can ONLY be executed by the gatekeeper role
public fun remove_collateral_manager_role(
    management: &mut DeUSDMintingManagement,
    global_config: &mut GlobalConfig,
    collateral_manager: address,
    ctx: &TxContext,
) {
    assert_package_version_and_initialized(management, global_config);
    assert_is_gatekeeper(global_config, ctx);

    config::remove_role_internal(global_config, collateral_manager, roles::role_collateral_manager());
}

/// Set delegated signer
public fun set_delegated_signer(
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    delegate_to: address,
    ctx: &mut TxContext,
) {
    assert_package_version_and_initialized(management, global_config);

    let sender = ctx.sender();
    if (!management.delegated_signers.contains(delegate_to)) {
        management.delegated_signers.add(delegate_to, table::new(ctx));
    };
    let delegate_map = management.delegated_signers.borrow_mut(delegate_to);
    delegate_map.add(sender, DELEGATED_SIGNER_STATUS_PENDING);

    event::emit(DelegatedSignerInitiated {
        signer: delegate_to,
        delegator: sender,
    });
}

/// Confirm delegated signer
public fun confirm_delegated_signer(
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    delegated_by: address,
    ctx: &TxContext,
) {
    assert_package_version_and_initialized(management, global_config);

    let sender = ctx.sender();
    assert!(management.delegated_signers.contains(sender), EDelegationNotInitiated);

    let delegate_map = management.delegated_signers.borrow_mut(sender);
    assert!(delegate_map.contains(delegated_by), EDelegationNotInitiated);

    let status = delegate_map.borrow_mut(delegated_by);
    assert!(*status == DELEGATED_SIGNER_STATUS_PENDING, EDelegationNotInitiated);
    *status = DELEGATED_SIGNER_STATUS_ACCEPTED;

    event::emit(DelegatedSignerAdded {
        signer: sender,
        delegator: delegated_by,
    });
}

/// Removes a delegated signer mapping (undelegates an address for signing)
public fun remove_delegated_signer(
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    removed_signer: address,
    ctx: &mut TxContext,
) {
    assert_package_version_and_initialized(management, global_config);

    let sender = ctx.sender();
    assert!(management.delegated_signers.contains(removed_signer), EDelegationNotInitiated);
    let delegate_map = management.delegated_signers.borrow_mut(removed_signer);
    assert!(delegate_map.contains(sender), EDelegationNotInitiated);
    *delegate_map.borrow_mut(sender) = DELEGATED_SIGNER_STATUS_REJECTED;

    event::emit(DelegatedSignerRemoved {
        signer: removed_signer,
        delegator: sender,
    });
}

/// Transfers an asset to a custody wallet.
public fun transfer_to_custody<T>(
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    wallet: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert_package_version_and_initialized(management, global_config);

    assert_is_collateral_manager(global_config, ctx);
    assert!(wallet != @0x0, EInvalidAddress);
    assert!(management.custodian_addresses.contains(wallet), EInvalidAddress);

    let contract_balance = get_or_create_balance_store_mut<T>(management);
    assert!(contract_balance.value() >= amount, EInvalidAmount);

    transfer::public_transfer(coin::from_balance(contract_balance.split(amount), ctx), wallet);

    event::emit(CustodyTransfer { wallet, asset: type_name::get<T>(), amount });
}

// === View Functions ===

/// Check if asset is supported
public fun is_supported_asset<T>(management: &DeUSDMintingManagement): bool {
    let asset = type_name::get<T>();
    management.supported_assets.contains(asset)
}

/// Get max mint per block
public fun get_max_mint_per_block(management: &DeUSDMintingManagement): u64 {
    management.max_mint_per_second
}

/// Get max redeem per block
public fun get_max_redeem_per_block(management: &DeUSDMintingManagement): u64 {
    management.max_redeem_per_second
}

/// Hash order for verification using individual parameters
public fun hash_order<Collateral>(
    order_type: u8,
    expiry: u64,
    nonce: u64,
    benefactor: address,
    beneficiary: address,
    collateral_amount: u64,
    deusd_amount: u64
): vector<u8> {
    let collateral_asset = type_name::get<Collateral>();

    let mut data = vector::empty<u8>();
    vector::append(&mut data, bcs::to_bytes(&order_type));
    vector::append(&mut data, bcs::to_bytes(&expiry));
    vector::append(&mut data, bcs::to_bytes(&nonce));
    vector::append(&mut data, bcs::to_bytes(&benefactor));
    vector::append(&mut data, bcs::to_bytes(&beneficiary));
    vector::append(&mut data, bcs::to_bytes(ascii::as_bytes(collateral_asset.borrow_string())));
    vector::append(&mut data, bcs::to_bytes(&collateral_amount));
    vector::append(&mut data, bcs::to_bytes(&deusd_amount));

    hash::keccak256(&data)
}

/// Verify route validity using individual parameters
public fun verify_route(
    addresses: vector<address>,
    ratios: vector<u64>,
    custodians: &Set<address>
): bool {
    if (vector::length(&addresses) != vector::length(&ratios)) {
        return false
    };

    if (vector::length(&addresses) == 0) {
        return false
    };

    let mut total_ratio = 0u64;
    let mut i = 0;
    while (i < vector::length(&addresses)) {
        let addr = addresses[i];
        let ratio = ratios[i];

        if (!custodians.contains(addr) || addr == @0x0 || ratio == 0) {
            return false
        };

        total_ratio = total_ratio + ratio;
        i = i + 1;
    };

    total_ratio == ROUTE_REQUIRED_RATIO
}

// === View Functions ===

public fun get_minted_per_second(management: &DeUSDMintingManagement, timestamp_seconds: u64): u64 {
    if (management.minted_per_second.contains(timestamp_seconds)) {
        *management.minted_per_second.borrow(timestamp_seconds)
    } else {
        0
    }
}

public fun get_redeemed_per_second(management: &DeUSDMintingManagement, timestamp_seconds: u64): u64 {
    if (management.redeemed_per_second.contains(timestamp_seconds)) {
        *management.redeemed_per_second.borrow(timestamp_seconds)
    } else {
        0
    }
}

public fun get_delegated_signer_status(management: &DeUSDMintingManagement, signer: address, delegator: address): u8 {
    if (management.delegated_signers.contains(signer)) {
        let delegate_map = management.delegated_signers.borrow(signer);
        if (delegate_map.contains(delegator)) {
            return *delegate_map.borrow(delegator)
        };
    };

    DELEGATED_SIGNER_STATUS_NO_STATUS
}

public fun get_balance<T>(
    management: &DeUSDMintingManagement,
): u64 {
    let balance_key = BalanceStoreKey<T> {};
    if (!df::exists_(&management.id, balance_key)) {
        return 0
    };

    let balance = df::borrow<BalanceStoreKey<T>, Balance<T>>(&management.id, BalanceStoreKey<T> {});
    balance.value()
}

// === Helper Functions ===

fun assert_package_version_and_initialized(
    management: &DeUSDMintingManagement,
    global_config: &GlobalConfig,
) {
    global_config.check_package_version();
    assert!(management.initialized, ENotInitialized);
}

fun assert_is_minter(config: &GlobalConfig, ctx: &TxContext) {
    assert!(config::has_role(config, ctx.sender(), roles::role_minter()), ENotAuthorized);
}

fun assert_is_redeemer(config: &GlobalConfig, ctx: &TxContext) {
    assert!(config::has_role(config, ctx.sender(), roles::role_redeemer()), ENotAuthorized);
}

fun assert_is_gatekeeper(config: &GlobalConfig, ctx: &TxContext) {
    assert!(config::has_role(config, ctx.sender(), roles::role_gate_keeper()), ENotAuthorized);
}

fun assert_is_collateral_manager(config: &GlobalConfig, ctx: &TxContext) {
    assert!(config::has_role(config, ctx.sender(), roles::role_collateral_manager()), ENotAuthorized);
}

fun verify_order<Collateral>(
    management: &DeUSDMintingManagement,
    order_type: u8,
    expiry: u64,
    nonce: u64,
    benefactor: address,
    beneficiary: address,
    collateral_amount: u64,
    deusd_amount: u64,
    public_key: vector<u8>,
    signature: vector<u8>,
    clock: &Clock,
) {
    let order_hash = hash_order<Collateral>(
        order_type,
        expiry,
        nonce,
        benefactor,
        beneficiary,
        collateral_amount,
        deusd_amount
    );
    assert!(ed25519::ed25519_verify(&signature, &public_key, &order_hash), EInvalidSignature);

    let signer = cryptography::ed25519_public_key_to_address(public_key);
    assert!(
        signer == benefactor ||
            get_delegated_signer_status(management, signer, benefactor) == DELEGATED_SIGNER_STATUS_ACCEPTED,
        EInvalidSignature,
    );

    assert!(beneficiary != @0x0, EInvalidAddress);
    assert!(collateral_amount > 0, EInvalidAmount);
    assert!(deusd_amount > 0, EInvalidAmount);
    assert!(clock_utils::timestamp_seconds(clock) <= expiry, ESignatureExpired);
}

fun deduplicate_order(
    management: &mut DeUSDMintingManagement,
    sender: address,
    nonce: u64,
    ctx: &mut TxContext,
) {
    assert!(nonce > 0, EInvalidNonce);

    let invalidator_slot = nonce >> 8;
    let invalidator_bit: u256 = 1 << ((nonce & 255) as u8);

    if (!management.order_bitmaps.contains(sender)) {
        management.order_bitmaps.add(sender, table::new(ctx));
    };

    let user_bitmap = management.order_bitmaps.borrow_mut(sender);

    if (!user_bitmap.contains(invalidator_slot)) {
        user_bitmap.add(invalidator_slot, 0);
    };

    let invalidator = user_bitmap.borrow_mut(invalidator_slot);
    assert!(*invalidator & invalidator_bit == 0, EInvalidNonce);
    *invalidator = *invalidator | invalidator_bit;
}

fun update_minted_per_second(management: &mut DeUSDMintingManagement, block: u64, amount: u64) {
    if (management.minted_per_second.contains(block)) {
        let current = management.minted_per_second.borrow_mut(block);
        *current = *current + amount;
    } else {
        management.minted_per_second.add(block, amount);
    }
}

fun update_redeemed_per_second(management: &mut DeUSDMintingManagement, second: u64, amount: u64) {
    if (management.redeemed_per_second.contains(second)) {
        let current = management.redeemed_per_second.borrow_mut(second);
        *current = *current + amount;
    } else {
        management.redeemed_per_second.add(second, amount);
    }
}

fun get_or_create_balance_store_mut<T>(
    management: &mut DeUSDMintingManagement,
): &mut Balance<T> {
    let balance_key = BalanceStoreKey<T> {};
    if (!df::exists_(&management.id, balance_key)) {
        df::add(&mut management.id, balance_key, balance::zero<T>());
    };

    df::borrow_mut(&mut management.id, balance_key)
}

fun add_custodian_address_internal(
    management: &mut DeUSDMintingManagement,
    custodian: address,
) {
    assert!(custodian != @0x0, EInvalidCustodianAddress);
    management.custodian_addresses.add(custodian);

    event::emit(CustodianAddressAdded { custodian });
}

fun set_max_mint_per_second_internal(
    management: &mut DeUSDMintingManagement,
    max_mint: u64,
) {
    let old_max = management.max_mint_per_second;
    management.max_mint_per_second = max_mint;

    event::emit(MaxMintPerSecondChanged {
        old_max,
        new_max: max_mint,
    });
}

fun set_max_redeem_per_second_internal(
    management: &mut DeUSDMintingManagement,
    max_redeem: u64,
) {
    let old_max = management.max_redeem_per_second;
    management.max_redeem_per_second = max_redeem;

    event::emit(MaxRedeemPerBlockChanged {
        old_max,
        new_max: max_redeem,
    });
}

/// Transfer supported asset to vector of custody addresses per defined ratio
fun transfer_collateral<T>(
    management: &mut DeUSDMintingManagement,
    mut collateral: Coin<T>,
    benefactor: address,
    addresses: vector<address>,
    ratios: vector<u64>,
    ctx: &mut TxContext,
) {
    let asset = type_name::get<T>();
    assert!(management.supported_assets.contains(asset), EUnsupportedAsset);

    let total_asset_amount = collateral.value();

    let mut i = 0;
    let addresses_length = vector::length(&addresses);
    while (i < addresses_length) {
        let ratio = ratios[i];
        let amount_to_transfer = math_u64::mul_div(total_asset_amount, ratio, ROUTE_REQUIRED_RATIO, false);
        let asset_to_transfer = collateral.split(amount_to_transfer, ctx);

        let recipient = addresses[i];
        if (recipient == management.address) {
            let contract_balance = get_or_create_balance_store_mut<T>(management);
            contract_balance.join(coin::into_balance(asset_to_transfer));
        } else {
            transfer::public_transfer(asset_to_transfer, addresses[i]);
        };

        i = i + 1;
    };

    if (collateral.value() > 0) {
        transfer::public_transfer(collateral, benefactor);
    } else {
        coin::destroy_zero(collateral);
    }
}

/// Transfer supported asset to beneficiary address
fun transfer_to_beneficiary<T>(
    management: &mut DeUSDMintingManagement,
    beneficiary: address,
    amount: u64,
    ctx: &mut TxContext,
) {
    let asset = type_name::get<T>();
    assert!(management.supported_assets.contains(asset), EUnsupportedAsset);

    let contract_balance = get_or_create_balance_store_mut<T>(management);

    transfer::public_transfer(coin::from_balance(contract_balance.split(amount), ctx), beneficiary);
}

// === Test Functions ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun set_delegated_signer_for_test(
    management: &mut DeUSDMintingManagement,
    signer: address,
    delegator: address,
    status: u8,
    ctx: &mut TxContext,
) {
    if (!management.delegated_signers.contains(signer)) {
        management.delegated_signers.add(signer, table::new(ctx));
    };
    let delegate_map = management.delegated_signers.borrow_mut(signer);
    delegate_map.add(delegator, status);
}

#[test_only]
public fun get_custodian_addresses_for_test(management: &DeUSDMintingManagement): &Set<address> {
    &management.custodian_addresses
}