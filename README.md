# Elixir deUSD smart contracts

## Requirements

- [Sui cli](https://docs.sui.io/guides/developer/getting-started/sui-install)

## Contract Overview

This repository contains the following modules organized into core functionality and utility libraries:

### Core Modules

#### `admin_cap.move`
Administrative capability module that provides secure access control for protocol management functions.

#### `config.move`
Global configuration management module that handles package versioning, role-based access control integration.

#### `roles.move`
Role definition module that establishes role constants for the access control system, including minter, redeemer, collateral manager, gatekeeper, rewarder, and blacklist manager roles, ...

#### `acl.move`
Access Control List for efficiently member roles management.

#### `deusd.move`
Implement `deUSD` token.

#### `wdeusd_vault.move`
Implement `wdeUSD` vault to facilitate bridging `deUSD` from `Ethereum` to `Sui`.

#### `deusd_minting.move`
Main minting and redemption module that processes collateral deposits and deUSD issuance.

#### `locked_funds.move`
Allow users to lock their collateral/`deUSD` tokens for minting/burning `deUSD`.

#### `deusd_lp_staking.move`
Allow liquidity providers to staking their LP tokens to receive rewards.

#### `sdeusd.move`
Staked deUSD implementation following ERC4626 vault standard. 

#### `staking_rewards_distributor.move`
Allow operator to transfer rewards into th `sd

## Integration documentation

- [External minting and burning deUSD](./docs/external_mint_burn.md)

## Development

**Note:** If you run into with any issues, try to run `make clean` to clean up the build cache and retry.

### Building the Project
```bash
sui move build -d
```

### Running Tests
```bash
sui move test
```

### Deploying to Network
- Update the `initial_rewarder` in the `Move.toml` file with appreciate value.

```bash
sui client publish
```

## Publish and initialize the package

### Publish the package

Follow the guide in the previous section to publish the package.

After publishing, check the publishing transaction to get the corresponding configurations (object IDs). Then, create a new .env file in the root folder from .env.example and update the values accordingly.

### Initialize minting contract

Run the following command to initialize the minting contract:

```bash
make initialize-minting
```

### Initialize wdeusd vault contract

Requirements: 
- The `wdeUSD` coin must be created by Sui bridge with 6 decimals before initializing the vault. Then update `WDEUSD_COIN_METADATA_ID` and `WDEUSD_TYPE` in the `.env` file.

Run the following command to initialize the vault contract:

```bash
make initialize-wdeusd-vault
```

## Functions

### `deUSD` module

#### Create `DeUSDTreasuryCap` for external contracts to mint/burn `deUSD` directly

The `DeUSDTreasuryCap` should be used for cross-chain bridges to mint/burn `deUSD`.

```bash
make create-deusd-treasury-cap to=${owner_account_address}
```

#### Active/de-active a created `DeUSDTreasuryCap`
This function should be used if a `DeUSDTreasuryCap` is compromised.

```bash
make set-deusd-treasury-cap-status treasury_cap_id=${deusd_treasury_cap_id} is_active=false
```