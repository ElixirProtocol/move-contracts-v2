#[test_only]
module elixir::test_utils;

// === Imports ===

use elixir::admin_cap;
use elixir::deusd_minting;
use elixir::config;

// === Public Functions ===

public fun setup_test(ctx: &mut TxContext) {
    admin_cap::init_for_test(ctx);
    config::init_for_test(ctx);
    deusd_minting::init_for_test(ctx);
}