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

## Usage documentation

- [deUSD staking](./docs/deusd_staking.md)

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

### Upgrading package

- Run the following command to get the upgrade object, get `UPGRADE_CAPABILITY` from the publishing transaction:

```bash
sui client upgrade -c <UPGRADE_CAPABILITY>
```

## Publish and initialize the package

### Publish the package

Follow the guide in the previous section to publish the package.

After publishing, check the publishing transaction to get the corresponding configurations (object IDs). Then, create a new .env file in the root folder from .env.example and update the values accordingly.

### Upgrade the package

Follow the guide in the previous section to upgrade the package. 
Remember to update the new value of `PACKAGE_VERSION` in the `config.move` module and commit this changes before upgrading.
After upgrading, check the upgrading transaction to get the new package ID and update the `PACKAGE_ID` in the `.env` file.

Then, run the following command to get upgrade package version:

```bash
make upgrade-package-version
```

### Initialize deUSD treasury cap config

Run the following command to initialize the deUSD treasury cap config:

```bash
make initialize-deusd-treasury-cap-config
```

**Note**: This step is required to allow external contracts to mint/burn deUSD via `DeUSDTreasuryCap` and should be done only once.

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

### Delete and re-initialize `deUSD` config

This is required if you want to transfer the `deUSD`'s treasury cap to another account to allow the new account 
to mint/burn `deUSD` directly, not used in normal operations because the contract will not be able to mint/burn `deUSD` 
util the new `deUSD` config is initialized.

#### Delete `deUSD` config

Actor: admin of the contract.

Run the following command to delete the `deUSD` config:

```bash
make delete-deusd-config caps_owner=${owners_of_treasury_cap_account_address}
```

**Note**: this command will transfer both `TreasuryCap` and `DenyCapV2` to the `caps_owner` address. 
You can find the object IDs of `TreasuryCap` and `DenyCapV2` by checking the content of the `DeUSDConfig` before deleting it.

#### Re-initialize `deUSD` config

Actor: anyone who owns the `TreasuryCap` and `DenyCapV2`.

Run the following command to re-initialize the `deUSD` config.

```bash
make initialize-deusd-config treasury_cap=${treasury_cap_id}  deny_cap=${deny_cap_id}
```

After re-initializing the `deUSD` config, please update the `DEUSD_CONFIG_ID` in the `.env` file.

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