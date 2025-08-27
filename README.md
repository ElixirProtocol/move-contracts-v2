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
