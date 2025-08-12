module elixir::config;

// === Imports ===

use sui::event;
use elixir::acl::{Self, ACL};
use elixir::admin_cap::AdminCap;

// === Error Codes ===

const ENewPackageVersionTooLow: u64 = 1;
const EPackageVersionMismatch: u64 = 2;

// === Constants ===

const PACKAGE_VERSION: u64 = 1;

// === Structs ===

public struct GlobalConfig has key {
    id: UID,
    acl: ACL,
    package_version: u64,
}

// === Events ===

public struct PackageVersionUpgraded has copy, drop {
    new_version: u64,
    old_version: u64,
}

public struct RoleAdded has copy, drop {
    member: address,
    role: u8,
}

public struct RoleRemoved has copy, drop {
    member: address,
    role: u8,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(GlobalConfig {
        id: object::new(ctx),
        acl: acl::new(ctx),
        package_version: PACKAGE_VERSION,
    });
}

// === Public Functions ===

public fun upgrade_package_version(_: &AdminCap, config: &mut GlobalConfig) {
    assert!(config.package_version < PACKAGE_VERSION, ENewPackageVersionTooLow);

    let old_package_version = config.package_version;
    config.package_version = PACKAGE_VERSION;

    event::emit(PackageVersionUpgraded {
        new_version: config.package_version,
        old_version: old_package_version,
    });
}

public fun add_role(
    _: &AdminCap,
    config: &mut GlobalConfig,
    member: address,
    role: u8,
) {
    config.check_package_version();

    add_role_internal(config, member, role);
}

public fun remove_role(
    _: &AdminCap,
    config: &mut GlobalConfig,
    member: address,
    role: u8,
) {
    config.check_package_version();

    remove_role_internal(config, member, role);
}

public fun remove_member(
    _: &AdminCap,
    config: &mut GlobalConfig,
    member: address,
) {
    config.check_package_version();

    config.acl.remove_member(member);
}

public fun has_role(config: &GlobalConfig, member: address, role: u8): bool {
    config.acl.has_role(member, role)
}

public fun check_package_version(config: &GlobalConfig) {
    assert!(config.package_version == PACKAGE_VERSION, EPackageVersionMismatch);
}

// === Internal Functions ===

public(package) fun add_role_internal(
    config: &mut GlobalConfig,
    member: address,
    role: u8,
) {
    config.acl.add_role(member, role);

    event::emit(RoleAdded {
        member,
        role,
    });
}

public(package) fun remove_role_internal(
    config: &mut GlobalConfig,
    member: address,
    role: u8,
) {
    config.acl.remove_role(member, role);

    event::emit(RoleRemoved {
        member,
        role,
    });
}

// === Tests ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun get_package_version(): u64 {
    PACKAGE_VERSION
}

#[test_only]
public fun create_for_test(ctx: &mut TxContext): GlobalConfig {
    GlobalConfig {
        id: object::new(ctx),
        acl: acl::new(ctx),
        package_version: PACKAGE_VERSION,
    }
}

#[test_only]
public fun create_with_custom_version_for_test(package_version: u64, ctx: &mut TxContext): GlobalConfig {
    GlobalConfig {
        id: object::new(ctx),
        acl: acl::new(ctx),
        package_version,
    }
}

#[test_only]
public fun destroy_for_test(config: GlobalConfig) {
    let GlobalConfig { id, acl, package_version: _ } = config;
    id.delete();
    sui::test_utils::destroy(acl);
}
