module elixir::set;

use sui::table::{Self, Table};

// === Structs ===

public struct Set<phantom T: store + drop + copy> has store {
    inner: Table<T, bool>,
}

// === Public Functions ===

public(package) fun new<T: store + drop + copy>(ctx: &mut TxContext): Set<T> {
    Set { inner: table::new<T, bool>(ctx) }
}

public(package) fun add<T: store + drop + copy>(s: &mut Set<T>, item: T) {
    if (!s.inner.contains(item)) {
        s.inner.add(item, true);
    };
}

public(package) fun remove<T: store + drop + copy>(s: &mut Set<T>, item: T) {
    s.inner.remove(item);
}

public(package) fun contains<T: store + drop + copy>(s: &Set<T>, item: T): bool {
    s.inner.contains(item)
}

public(package) fun length<T: store + drop + copy>(s: &Set<T>): u64 {
    s.inner.length()
}