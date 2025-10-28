# deUSD staking

## Cooldown and unrestricted staking

By default, deUSD staking uses a 7-day cooldown period: when a user unstakes, they must wait 7 days before withdrawing their staked tokens.

In some situations you may want to allow certain accounts to withdraw staked tokens immediately without the cooldown. This document explains how to grant and revoke that permission safely.

### Overview

- The special permission is called the "cooldown unrestricted staker manager" role. An account with this role can mark specific stakers as "cooldown-unrestricted", letting them withdraw stakes instantly.
- Only the contract admin can grant or revoke the manager role.

### Grant the manager role

Run the following to grant the manager role (`role = 6`) to an account:

```sh
make add-role address={manager-address} role=6
```

Replace `{manager-address}` with the manager's account address.

Note: This command can only be run by the contract admin.

### Add an unrestricted staker

Once an account has the manager role, it can enable unrestricted staking for a specific staker with:

```sh
make add-cooldown-unrestricted-staker staker={staker-address}
```

After this command, the specified staker can withdraw their staked deUSD tokens immediately (no cooldown).

Note: this command can only be run by an account with the `cooldown unrestricted staker manager` role.

### Revoke unrestricted staking for a staker

If you need to remove unrestricted withdrawal privileges from a staker, the manager can run:

```sh
make remove-cooldown-unrestricted-staker staker={staker-address}
```

Note: this command can only be run by an account with the `cooldown unrestricted staker manager` role.

### Other notes

- Because we use role-based access control for the cooldown unrestricted stakers (`role = 7`), the admin can also manage the unrestricted stakers by adding/removing the role directly if needed.
