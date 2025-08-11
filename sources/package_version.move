module elixir::package_version;

use elixir::admin_cap::AdminCap;
use sui::event;

// === Error Codes ===

const ENewPackageVersionTooLow: u64 = 1;
const EPackageVersionMismatch: u64 = 2;

// === Constants ===

const PACKAGE_VERSION: u64 = 1;

// === Structs ===

public struct PackageVersion has key {
    id: UID,
    version: u64,
}

// === Events ===

public struct PackageVersionUpgraded has copy, drop {
    new_version: u64,
    old_version: u64,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(PackageVersion {
        id: object::new(ctx),
        version: PACKAGE_VERSION,
    });
}

// === Public Functions ===

public fun update_package_version(_: &AdminCap, package_version: &mut PackageVersion) {
    assert!(package_version.version < PACKAGE_VERSION, ENewPackageVersionTooLow);

    let old_version = package_version.version;
    package_version.version = PACKAGE_VERSION;

    event::emit(PackageVersionUpgraded {
        new_version: PACKAGE_VERSION,
        old_version,
    });
}

public fun check_package_version(config: &PackageVersion) {
    assert!(config.version == PACKAGE_VERSION, EPackageVersionMismatch);
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
public fun create_for_test(ctx: &mut TxContext): PackageVersion {
    PackageVersion {
        id: object::new(ctx),
        version: PACKAGE_VERSION,
    }
}

#[test_only]
public fun create_with_custom_version_for_test(version: u64, ctx: &mut TxContext): PackageVersion {
    PackageVersion {
        id: object::new(ctx),
        version,
    }
}

#[test_only]
public fun destroy_for_test(package_version: PackageVersion) {
    let PackageVersion { id, version: _ } = package_version;
    id.delete();
}