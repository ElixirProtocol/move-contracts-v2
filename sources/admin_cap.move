module elixir::admin_cap;

// === Structs ===

public struct AdminCap has key {
    id: UID,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    let admin_cap = AdminCap { id: object::new(ctx) };
    transfer::transfer(admin_cap, ctx.sender());
}

// === Tests ===

#[test_only]
public fun init_for_test(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun create_for_test(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}

#[test_only]
public fun destroy_for_test(admin_cap: AdminCap) {
    let AdminCap { id } = admin_cap;
    id.delete();
}