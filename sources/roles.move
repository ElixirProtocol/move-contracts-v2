module elixir::roles;

// === Constants ===

const ROLE_MINTER: u8 = 0;
const ROLE_REDEEMER: u8 = 1;
const ROLE_COLLATERAL_MANAGER: u8 = 2;
const ROLE_GATE_KEEPER: u8 = 3;
const ROLE_REWARDER: u8 = 4;
const ROLE_BLACKLIST_MANAGER: u8 = 5;

// === Public Functions ===

public fun role_minter(): u8 {
    ROLE_MINTER
}

public fun role_redeemer(): u8 {
    ROLE_REDEEMER
}

public fun role_collateral_manager(): u8 {
    ROLE_COLLATERAL_MANAGER
}

public fun role_gate_keeper(): u8 {
    ROLE_GATE_KEEPER
}

public fun role_rewarder(): u8 {
    ROLE_REWARDER
}

public fun role_blacklist_manager(): u8 {
    ROLE_BLACKLIST_MANAGER
}