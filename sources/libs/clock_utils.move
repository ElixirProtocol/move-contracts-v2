module elixir::clock_utils;

// === Imports ===

use sui::clock::Clock;

// === Public Functions ===

public(package) fun timestamp_seconds(clock: &Clock): u64 {
    clock.timestamp_ms() / 1000
}