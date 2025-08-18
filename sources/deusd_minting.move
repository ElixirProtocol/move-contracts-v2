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
use elixir::locked_funds::{Self, LockedFundsManagement};
use elixir::roles;
use elixir::set::{Self, Set};

// === Error codes ===

/// The module is initialized, could not be initialized again.
const EInitialized: u64 = 0;
/// The module is not initialized.
const ENotInitialized: u64 = 1;
/// Invalid route.
const EInvalidRoute: u64 = 2;
/// Max mint per second exceeded.
const EMaxMintPerSecondExceeded: u64 = 3;
/// Max redeem per second exceeded.
const EMaxRedeemPerSecondExceeded: u64 = 4;
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
/// Not authorized.
const ENotAuthorized: u64 = 11;
/// Invalid signature.
const EInvalidSignature: u64 = 12;
/// Invalid signer.
const EInvalidSigner: u64 = 13;
/// Not enough amount for the operation.
const ENotEnoughAmount: u64 = 14;

// === Constants ===

const ORDER_TYPE_MINT: u8 = 0;
const ORDER_TYPE_REDEEM: u8 = 1;

/// Required ratio for route (10000 = 100%)
const ROUTE_REQUIRED_RATIO: u64 = 10_000;

const ORDER_DOMAIN_SEPARATOR: vector<u8> = b"deusd_order";

// === Structs ===

public struct DeUSDMintingManagement has key {
    id: UID,
    /// Initialization address of the contract
    package_address: address,
    domain_separator: vector<u8>,
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

public struct MaxRedeemPerSecondChanged has copy, drop, store {
    old_max: u64,
    new_max: u64,
}

public struct CustodyTransfer has copy, drop, store {
    wallet: address,
    asset: TypeName,
    amount: u64,
}

public struct Deposit has copy, drop, store {
    depositor: address,
    asset: TypeName,
    amount: u64,
}

public struct Withdraw has copy, drop, store {
    asset: TypeName,
    amount: u64,
    recipient: address,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    let management = DeUSDMintingManagement {
        id: object::new(ctx),
        package_address: @0x0,
        domain_separator: vector::empty(),
        supported_assets: set::new(ctx),
        custodian_addresses: set::new(ctx),
        order_bitmaps: table::new(ctx),
        minted_per_second: table::new(ctx),
        redeemed_per_second: table::new(ctx),
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
    package_address: address,
    custodians: vector<address>,
    max_mint_per_second: u64,
    max_redeem_per_second: u64,
) {
    global_config.check_package_version();
    assert!(!management.initialized, EInitialized);

    management.initialized = true;
    management.package_address = package_address;
    management.domain_separator = calculate_domain_separator(package_address);

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
    locked_funds_management: &mut LockedFundsManagement,
    deusd_management: &mut DeUSDConfig,
    global_config: &GlobalConfig,
    expiry: u64,
    nonce: u64,
    benefactor: address,
    beneficiary: address,
    collateral_amount: u64,
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
    assert!(current_minted + deusd_amount <= management.max_mint_per_second, EMaxMintPerSecondExceeded);

    deduplicate_order(management, benefactor, nonce, ctx);

    // Update minted amount for this second
    update_minted_per_second(management, now_seconds, deusd_amount);

    let collateral = locked_funds::withdraw_internal<T>(locked_funds_management, benefactor, collateral_amount, ctx);
    transfer_collateral(management, collateral, route_addresses, route_ratios, ctx);

    deusd::mint(deusd_management, beneficiary, deusd_amount, ctx);

    event::emit(Mint {
        minter: ctx.sender(),
        benefactor,
        beneficiary,
        collateral_asset: type_name::get<T>().into_string(),
        collateral_amount,
        deusd_amount,
    });
}

/// Redeem deUSD for collateral assets
public fun redeem<T>(
    management: &mut DeUSDMintingManagement,
    locked_funds_management: &mut LockedFundsManagement,
    deusd_config: &mut DeUSDConfig,
    global_config: &GlobalConfig,
    // Order parameters
    expiry: u64,
    nonce: u64,
    benefactor: address,
    beneficiary: address,
    collateral_amount: u64,
    deusd_amount: u64,
    public_key: vector<u8>,
    signature: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_package_version_and_initialized(management, global_config);
    assert_is_redeemer(global_config, ctx);

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
    assert!(current_redeemed + deusd_amount <= management.max_redeem_per_second, EMaxRedeemPerSecondExceeded);

    deduplicate_order(management, benefactor, nonce, ctx);

    update_redeemed_per_second(management, now_seconds, deusd_amount);

    let deusd_coins = locked_funds::withdraw_internal<DEUSD>(locked_funds_management, benefactor, deusd_amount, ctx);
    deusd::burn_from(deusd_config, deusd_coins, benefactor);

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

    set_max_mint_per_second_internal(management, 0);
    set_max_redeem_per_second_internal(management, 0)
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

/// Deposit coins into the minting contract for redeeming later.
/// This allows anyone to deposit coins.
public fun deposit<T>(
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    coins: Coin<T>,
    ctx: &TxContext,
) {
    assert_package_version_and_initialized(management, global_config);

    let amount = coins.value();
    assert!(amount > 0, EInvalidAmount);

    let balance = get_or_create_balance_store_mut<T>(management);
    balance.join(coin::into_balance(coins));

    event::emit(Deposit {
        depositor: ctx.sender(),
        asset: type_name::get<T>(),
        amount,
    });
}

/// Withdraw coins from the minting contract.
/// This allows only the admin to withdraw coins.
public fun withdraw<T>(
    _: &AdminCap,
    management: &mut DeUSDMintingManagement,
    global_config: &GlobalConfig,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    assert_package_version_and_initialized(management, global_config);
    assert!(amount > 0, EInvalidAmount);
    assert!(recipient != @0x0, EInvalidAddress);

    let balance = get_or_create_balance_store_mut<T>(management);
    assert!(balance.value() >= amount, ENotEnoughAmount);

    let withdrawn_coins = coin::from_balance(balance.split(amount), ctx);
    transfer::public_transfer(withdrawn_coins, recipient);

    event::emit(Withdraw {
        asset: type_name::get<T>(),
        amount,
        recipient,
    });
}

// === View Functions ===

public fun get_domain_separator(management: &DeUSDMintingManagement): vector<u8> {
    management.domain_separator
}

/// Check if asset is supported
public fun is_supported_asset<T>(management: &DeUSDMintingManagement): bool {
    let asset = type_name::get<T>();
    management.supported_assets.contains(asset)
}

/// Get max mint per second
public fun get_max_mint_per_second(management: &DeUSDMintingManagement): u64 {
    management.max_mint_per_second
}

/// Get max redeem per second
public fun get_max_redeem_per_second(management: &DeUSDMintingManagement): u64 {
    management.max_redeem_per_second
}

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

/// Hash order for verification using individual parameters
public fun hash_order<Collateral>(
    management: &DeUSDMintingManagement,
    order_type: u8,
    expiry: u64,
    nonce: u64,
    benefactor: address,
    beneficiary: address,
    collateral_amount: u64,
    deusd_amount: u64
): vector<u8> {
    let collateral_asset = type_name::get<Collateral>();

    let mut data = management.domain_separator;
    vector::append(&mut data, ORDER_DOMAIN_SEPARATOR);
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

fun calculate_domain_separator(addr: address): vector<u8> {
    let mut data = vector::empty<u8>();
    vector::append(&mut data, bcs::to_bytes(&addr));
    vector::append(&mut data, b"deusd_minting");
    hash::keccak256(&data)
}

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
    assert!(beneficiary != @0x0, EInvalidAddress);
    assert!(collateral_amount > 0, EInvalidAmount);
    assert!(deusd_amount > 0, EInvalidAmount);
    assert!(clock_utils::timestamp_seconds(clock) <= expiry, ESignatureExpired);

    let order_hash = hash_order<Collateral>(
        management,
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
    assert!(signer == benefactor, EInvalidSigner);
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

fun update_minted_per_second(management: &mut DeUSDMintingManagement, timestamp_seconds: u64, amount: u64) {
    if (management.minted_per_second.contains(timestamp_seconds)) {
        let current = management.minted_per_second.borrow_mut(timestamp_seconds);
        *current = *current + amount;
    } else {
        management.minted_per_second.add(timestamp_seconds, amount);
    }
}

fun update_redeemed_per_second(management: &mut DeUSDMintingManagement, timestamp_seconds: u64, amount: u64) {
    if (management.redeemed_per_second.contains(timestamp_seconds)) {
        let current = management.redeemed_per_second.borrow_mut(timestamp_seconds);
        *current = *current + amount;
    } else {
        management.redeemed_per_second.add(timestamp_seconds, amount);
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
    assert!(custodian != @0x0 || management.custodian_addresses.contains(custodian), EInvalidCustodianAddress);
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

    event::emit(MaxRedeemPerSecondChanged {
        old_max,
        new_max: max_redeem,
    });
}

/// Transfer supported asset to vector of custody addresses per defined ratio
fun transfer_collateral<T>(
    management: &mut DeUSDMintingManagement,
    mut collateral: Coin<T>,
    addresses: vector<address>,
    ratios: vector<u64>,
    ctx: &mut TxContext,
) {
    let asset = type_name::get<T>();
    assert!(management.supported_assets.contains(asset), EUnsupportedAsset);

    let total_asset_amount = collateral.value();

    let mut i = 0;
    let addresses_length = addresses.length();
    while (i < addresses_length - 1) {
        let ratio = ratios[i];
        let amount_to_transfer = math_u64::mul_div(total_asset_amount, ratio, ROUTE_REQUIRED_RATIO, false);
        let asset_to_transfer = collateral.split(amount_to_transfer, ctx);
        transfer_collateral_to(management, asset_to_transfer, addresses[i]);

        i = i + 1;
    };

    transfer_collateral_to(management, collateral, addresses[addresses_length - 1]);
}

fun transfer_collateral_to<T>(
    management: &mut DeUSDMintingManagement,
    collateral: Coin<T>,
    recipient: address,
) {
    if (recipient == management.package_address) {
        let contract_balance = get_or_create_balance_store_mut<T>(management);
        contract_balance.join(coin::into_balance(collateral));
    } else {
        transfer::public_transfer(collateral, recipient);
    };
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
public fun get_custodian_addresses_for_test(management: &DeUSDMintingManagement): &Set<address> {
    &management.custodian_addresses
}