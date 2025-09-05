#[test_only]
module elixir::test_wdeusd;

// === Imports ===

use sui::coin;

// === Structs ===

public struct TEST_WDEUSD has drop {}

// === Public Functions ===

public fun init_test_wdeusd(decimals: u8, ctx: &mut TxContext) {
    let (treasury_cap, coin_metadata) = coin::create_currency(
        TEST_WDEUSD {},
        decimals,
        b"WDEUSD",
        b"Wrapped DeUSD",
        b"Wrapped DeUSD",
        option::none(),
        ctx
    );

    transfer::public_share_object(treasury_cap);
    transfer::public_share_object(coin_metadata);
}