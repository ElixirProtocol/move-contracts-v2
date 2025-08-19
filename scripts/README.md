
# Scripts

This folder contains scripts and examples to interact with the contract.


## Setup

Suppose you have deployed the contract. Please create a `.env` file from `.env.example` and fill in the appropriate values.


## Test Coin

- Folder: `test_coin`
- This is a simple contract for creating test coins. If you don't want to test the contract with real collateral coins, please deploy this contract and mint coins to your wallet for testing. Read more details in the `README.md` file of this contract.


## Mint Order

### Step 1: Lock funds in the contract

```sh
make deposit-to-locked-funds coins={coin-object-id}
```

### Step 2: Mint order

Update the values of the mint order in `deusd-minting-demo.ts` as desired, then run the command below.

```sh
yarn deusd-minting-demo
```