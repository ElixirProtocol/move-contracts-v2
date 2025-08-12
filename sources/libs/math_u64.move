module elixir::math_u64;

// === Error Codes ===

const EDivisionByZero: u64 = 1;

// === Functions ===

public(package) fun mul_div(a: u64, b: u64, c: u64): u64 {
    assert!(c != 0, EDivisionByZero);

    let a = a as u128;
    let b = b as u128;
    let c = c as u128;

    ((a * b) / c) as u64
}