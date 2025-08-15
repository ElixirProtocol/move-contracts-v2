module elixir::math_u64;

// === Error Codes ===

const EDivisionByZero: u64 = 1;

// === Functions ===

public(package) fun mul_div(a: u64, b: u64, c: u64, rounding_up: bool): u64 {
    assert!(c != 0, EDivisionByZero);

    let product = (a as u128) * (b as u128);
    let c = (c as u128);

    if (product == 0) {
        return 0
    };

    if (rounding_up) {
        ((product - 1) / c + 1 as u64)
    } else {
        ((product / c) as u64)
    }
}