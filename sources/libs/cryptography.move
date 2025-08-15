module elixir::cryptography;

// === Imports ===

use sui::address;
use sui::hash;

// === Constants ===

const ED25519_ADDRESS_PREFIX: vector<u8> = x"00";

// === Public Functions ===

public(package) fun ed25519_public_key_to_address(public_key: vector<u8>): address {
    let mut data = vector[];
    vector::append(&mut data, ED25519_ADDRESS_PREFIX);
    vector::append(&mut data, public_key);

    address::from_bytes(hash::blake2b256(&data))
}