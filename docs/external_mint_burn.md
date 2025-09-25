# External minting and burning deUSD

This document guides other contracts on how to mint and burn `deUSD` tokens directly without interacting with the `deusd_minting` module. This is useful for integrating with contracts that need to manage deUSD supply, such as cross-chain bridges or other financial protocols.

## Steps to Enable External Minting/Burning

### Prerequisites

- Contact the Elixir team to obtain the object IDs of `DeUSDConfig` and `GlobalConfig` from the deployed `deusd` package. These configurations are required to call mint and burn functions.

### 1. Create a `DeUSDTreasuryCap`

As a developer of an external contract, request the Elixir team to create a `DeUSDTreasuryCap` that will be transferred to an account controlled by your team. This is done by running the `deusd::create_treasury_cap` function from an admin account. This capability will be used to authorize minting and burning of `deUSD` tokens.

```move
public fun create_treasury_cap(
    _: &AdminCap,
    deusd_config: &mut DeUSDConfig,
    global_config: &GlobalConfig,
    to: address,
    ctx: &mut TxContext,
) 
```

### 2. Integrate with `deusd` in Your External Contract

Assuming you have imported the interface of the `deusd` contract in your contract, there are two options to integrate with the `deusd` module:

#### Option 1: Use the Owner Account of the `DeUSDTreasuryCap` to Call Mint/Burn Functions

Write functions in your contract that call `deusd::mint_with_cap` and `deusd::burn_with_cap` functions, passing the `DeUSDTreasuryCap` as an argument. The owner of the account holding the `DeUSDTreasuryCap` must sign the transaction.

Below are examples of mint and burn functions in your contract:

```move
// YourContract.move

public fun mint_deusd_example(
    deusd_treasury_cap: &DeUSDTreasuryCap,
    deusd_config: &mut DeUSDConfig,
    deusd_global_config: &GlobalConfig,
    to: address,
    amount: u64,
    // other params based on your logic
    ctx: &mut TxContext,
) {
    // Implement your logic here

    deusd::mint_with_cap(
        deusd_treasury_cap,
        deusd_config,
        deusd_global_config,
        to,
        amount,
        ctx,
    );
    
    // Implement additional logic here
}

public fun burn_deusd_example(
    deusd_treasury_cap: &DeUSDTreasuryCap,
    deusd_config: &mut DeUSDConfig,
    deusd_global_config: &GlobalConfig,
    deusd_coin: Coin<DeUSD>,
    from: address,
    // other params based on your logic
    ctx: &mut TxContext,
) {
    // Implement your logic here

    deusd::burn_with_cap(
        deusd_treasury_cap,
        deusd_config,
        deusd_global_config,
        deusd_coin,
        from,
    );
    
    // Implement additional logic here
}
```

#### Option 2: Transfer the `DeUSDTreasuryCap` to Your Contract

In this option, your contract will own the `DeUSDTreasuryCap` and can call mint/burn functions without requiring the owner account of the `DeUSDTreasuryCap` to sign transactions.

First, transfer the `DeUSDTreasuryCap` to your contract by adding a transfer function in your contract and using the standard Sui object transfer mechanism (such as `transfer::transfer` or `transfer::share_object`) from the account that owns the `DeUSDTreasuryCap` from step 1.

```move
// YourContract.move

struct DeUSDTreasuryCapHolder has key, store {
    id: UID,
    treasury_cap: DeUSDTreasuryCap,
}

public fun set_treasury_cap(
    deusd_treasury_cap: DeUSDTreasuryCap,
    ctx: &mut TxContext,
) {
    let treasury_cap_holder = DeUSDTreasuryCapHolder {
        id: object::new(ctx),
        treasury_cap: deusd_treasury_cap,
    };
    
    // You can make treasury_cap_holder a public object or owned by someone with access control depending on your logic
    transfer::share_object(treasury_cap_holder);
}
```

Then, write mint and burn functions in your contract that call the `deusd::mint_with_cap` and `deusd::burn_with_cap` functions.

```move
// YourContract.move

public fun mint_deusd_example(
    treasury_cap_holder: &DeUSDTreasuryCapHolder,
    deusd_config: &mut DeUSDConfig,
    deusd_global_config: &GlobalConfig,
    to: address,
    amount: u64,
    // other params based on your logic
    ctx: &mut TxContext,
) {
    // Implement your logic here

    deusd::mint_with_cap(
        &treasury_cap_holder.treasury_cap,
        deusd_config,
        deusd_global_config,
        to,
        amount,
        ctx,
    );
    
    // Implement additional logic here
}

public fun burn_deusd_example(
    treasury_cap_holder: &DeUSDTreasuryCapHolder,
    deusd_config: &mut DeUSDConfig,
    deusd_global_config: &GlobalConfig,
    deusd_coin: Coin<DeUSD>,
    from: address,
    // other params based on your logic
    ctx: &mut TxContext,
) {
    // Implement your logic here

    deusd::burn_with_cap(
        &treasury_cap_holder.treasury_cap,
        deusd_config,
        deusd_global_config,
        deusd_coin,
        from,
        ctx,
    );

    // Implement additional logic here
}
```