# Test coin

This contract is for deploying coins for testing purposes on SUI.

## Requirements

- `Make` installed
- SUI CLI installed
- SUI wallet with sufficient funds (could be a testnet wallet)

## Usage

### Deploy the contract

```bash
sui client publish
```

After deploying the contract, you will receive a package ID and a USDC's management object ID. You could use explorer to check the transaction https://testnet.suivision.xyz/
Create a `.env` file in this folder and update it with the appropriate values.

### Mint coins

```bash
make mint to=<address> amount=<amount>
```

Example:

```bash
make mint to=0x1234567890abcdef1234567890abcdef123456789 amount=100000000
```