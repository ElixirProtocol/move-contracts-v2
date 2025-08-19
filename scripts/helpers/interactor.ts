// import { Keypair } from "@mysten/sui.js/cryptography";
// import {
//   CoinStruct,
//   PaginatedCoins,
//   SuiClient,
//   SuiTransactionBlockResponse,
//   SuiTransactionBlockResponseOptions,
// } from "@mysten/sui.js/client";
// import {
//   TransactionBlock,
//   TransactionObjectInput,
// } from "@mysten/sui.js/transactions";
// import BigNumber from "bignumber.js";
// import {
//   BigNumberable,
//   RewardPool,
//   SUI_CLIENT,
//   TOKEN_DECIMALS,
//   USDC_DECIMALS,
//   hexStrToUint8,
//   sleep,
//   toBaseNumber,
//   toBigNumber,
//   toBigNumberStr,
// } from "./utils";
// import { RewardsPayload, bcs } from "./signer";
//
// export class Interactor {
//   suiClient: SuiClient;
//   signer: Keypair;
//   // TODO: define interface for deployment file
//   deployment: any;
//
//   constructor(_suiClient: SuiClient, _deployment: any, _signer?: Keypair) {
//     this.suiClient = _suiClient;
//     this.deployment = _deployment;
//     // could be undefined, if initializing the interactor for only get calls
//     this.signer = _signer as Keypair;
//   }
//
//   /// signs and executes the provided sui transaction block
//   static async signAndExecuteTxBlock(
//     transactionBlock: TransactionBlock,
//     signer: Keypair,
//     suiClient?: SuiClient,
//     options: SuiTransactionBlockResponseOptions = {
//       showObjectChanges: true,
//       showEffects: true,
//       showEvents: true,
//       showInput: true,
//     },
//   ): Promise<SuiTransactionBlockResponse> {
//     const client = suiClient || SUI_CLIENT;
//     transactionBlock.setSenderIfNotSet(signer.toSuiAddress());
//     const builtTransactionBlock = await transactionBlock.build({
//       client,
//     });
//
//     const transactionSignature = await signer.signTransactionBlock(
//       builtTransactionBlock,
//     );
//
//     return client.executeTransactionBlock({
//       transactionBlock: builtTransactionBlock,
//       signature: transactionSignature.signature,
//       options,
//     });
//   }
//
//   /**
//    * Allows the caller to create the vault
//    * @param perpetualName name of the perpetual (ETH-PERP) for which the vault is being created
//    * @param operator the address of the trading account that will trade using vaults funds
//    * @returns SuiTransactionBlockResponse
//    */
//   async createVault(
//     perpetualName: string,
//     operator: String,
//   ): Promise<SuiTransactionBlockResponse> {
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.AdminCap),
//         txb.object(this.deployment.BluefinSubAccounts),
//         txb.object(this.deployment.BluefinBank),
//         txb.object(this.deployment.BluefinVaultStore),
//         txb.pure(this.getPerpetualID(perpetualName)),
//         txb.pure(operator),
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.Package}::bluefin_vault::create_vault`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows admin of the protocol to create reward pools
//    * @param rewardCoin The reward coin that will be funded into the pool and then claimed by users
//    * @param controller The operator that will be creating reward signatures
//    * @returns
//    */
//   async createRewardPool(
//     rewardCoin: string,
//     controller?: string,
//   ): Promise<SuiTransactionBlockResponse> {
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.AdminCap),
//         txb.pure(controller || this.signer.toSuiAddress()),
//       ],
//       typeArguments: [rewardCoin],
//       target: `${this.deployment.Package}::distributor::create_reward_pool`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows the caller to fund a rewards pool
//    * @param pool the reward pool to which the amount will be deposited
//    * @param amount the amount to be deposited into the pool (must be in base number, the method adds 9 decimal places)
//    * @returns SuiTransactionBlockResponse
//    */
//   async checkRewardsInRewardPool(pool: RewardPool, coin?: string) {
//     const obj = await this.suiClient.getObject({
//       id: pool.id,
//       options: {
//         showContent: true,
//       },
//     });
//
//     const rewardAmount = (obj.data?.content as any).fields.reward_balance;
//
//     return rewardAmount;
//   }
//
//   /**
//    * Allows the caller to fund a rewards pool
//    * @param pool the reward pool to which the amount will be deposited
//    * @param amount the amount to be deposited into the pool (must be in base number, the method adds 9 decimal places)
//    * @returns SuiTransactionBlockResponse
//    */
//   async fundRewardPool(pool: RewardPool, amount: BigNumberable, coin?: string) {
//     const txb = new TransactionBlock();
//
//     const args = [txb.object(pool.id)];
//
//     // if the coin object id is provided, just simply deposit the entire coin
//     if (coin) {
//       args.push(txb.object(coin));
//     } else {
//       // else first make a coin of the provided `amount` from user balance
//
//       // make a coin equal to the amount we want to fund the rewards pool with
//       await this.splitCoin(amount, pool.coin);
//       await sleep(3000);
//
//       // fetch the coin
//       const coin = await this.getCoinWithExactBalance(amount, pool.coin);
//
//       // add to args
//       args.push(txb.object(coin.coinObjectId));
//     }
//
//     txb.moveCall({
//       arguments: args,
//       typeArguments: [pool.coin],
//       target: `${this.deployment.Package}::distributor::fund_rewards_pool`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows caller to set the vault bank manager on the bluefin vault store
//    * The caller must be the admin of provided vault store
//    * @param manager address of new bank manager
//    * @returns SuiTransactionBlockResponse
//    */
//   async setVaultBankManager(
//     manager: string,
//   ): Promise<SuiTransactionBlockResponse> {
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.BluefinVaultStore),
//         txb.pure(manager),
//       ],
//       target: `${this.deployment.BluefinPackage}::vaults::set_vaults_bank_manger`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows caller to set the vault bank manager on the bluefin vault store
//    * The caller must be the admin of provided vault store
//    * @param manager address of new bank manager
//    * @returns SuiTransactionBlockResponse
//    */
//   async setVaultOperator(
//     vaultName: string,
//     operator: string,
//   ): Promise<SuiTransactionBlockResponse> {
//     const vault = this.getVaultID(vaultName);
//
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.AdminCap),
//         txb.object(vault),
//         txb.object(this.deployment.BluefinSubAccounts),
//         txb.object(this.deployment.BluefinVaultStore),
//         txb.pure(operator),
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.Package}::bluefin_vault::update_vault_operator`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows caller to set the admin of vault store
//    * The caller must be the admin of provided vault store
//    * @param admin address of new admin
//    * @returns SuiTransactionBlockResponse
//    */
//   async setAdmin(admin: string): Promise<SuiTransactionBlockResponse> {
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.BluefinVaultStore),
//         txb.pure(admin),
//       ],
//       target: `${this.deployment.BluefinPackage}::vaults::set_admin`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows caller to set the controller of a reward pool
//    * The caller must be the admin of package
//    * @param controller address of new controller
//    * @returns SuiTransactionBlockResponse
//    */
//   async setController(
//     pool: string,
//     controller: string,
//   ): Promise<SuiTransactionBlockResponse> {
//     const txb = new TransactionBlock();
//
//     const rewardsPool = this.deployment["RewardPools"][pool];
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.AdminCap),
//         txb.object(rewardsPool.id),
//         txb.pure(controller),
//       ],
//       typeArguments: [rewardsPool.coin],
//       target: `${this.deployment.Package}::distributor::update_rewards_controller`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows caller to pause a vault
//    * The caller must be the admin of provided vault store
//    * @param vaultName name of the vault(perpetual name ETH-PERP/BTC-PERP etc..)
//    * @param pause boolean value to pause/unpause the vault
//    * @returns SuiTransactionBlockResponse
//    */
//   async pauseVault(
//     vaultName: string,
//     pauseDeposit: boolean,
//     pauseWithdraw: boolean,
//     pauseClaim: boolean,
//   ): Promise<SuiTransactionBlockResponse> {
//     const vault = this.getVaultID(vaultName);
//
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.AdminCap),
//         txb.object(vault),
//         txb.pure.bool(pauseDeposit),
//         txb.pure.bool(pauseWithdraw),
//         txb.pure.bool(pauseClaim),
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.Package}::bluefin_vault::pause_vault`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows users to deposit USDC into the vault of their choice
//    * @param vaultName name of the vault(perpetual name ETH-PERP/BTC-PERP etc..)
//    * @param amount the amount of usdc to deposit
//    * @param options optional arguments
//    *  - receiver: the address of the user that will receive deposited amount rewards on elixir
//    *  - coinId: the id of supported usdc coin to be used for deposits. Please ensure that the coin has enough balance.
//    * @returns SuiTransactionBlockResponse
//    */
//   async depositToVault(
//     vaultName: string,
//     amount: BigNumberable,
//     options?: {
//       receiver?: string;
//       coinId?: string;
//     },
//   ): Promise<SuiTransactionBlockResponse> {
//     const receiver = options?.receiver || this.signer.toSuiAddress();
//
//     let coinID = options?.coinId;
//     // if no coin id is provided, search for the coin that user holds
//     // having balance >= amount
//     if (!coinID) {
//       coinID = (await this.getUSDCoinHavingBalance(amount)).coinObjectId;
//     }
//
//     const vault = this.getVaultID(vaultName);
//
//     const txb = new TransactionBlock();
//
//     /// - bluefin_perpetual: Immutable reference to bluefin's perpetual that is supported by the vault
//     /// - bluefin_bank: The margin bank of bluefin that we need to deposit/withdraw money into or from
//     /// - bluefin_sequencer: The sequner of bluefin used to assign a unique incremental transaction index to each call
//     /// - vault: Mutable reference to the Vault in which coins are to be deposited/locked
//     /// - coin : Mutable reference to the <T> type coin holding the funds to be locked/deposited
//     /// - amount: quantity of coins to be locked - this must be in 1e6 format
//     /// - receiver: address of the user for which the money will be locked. They will be the one earning rewards
//     /// - ctx: Mutable reference to `TxContext`, the transaction context.
//
//     // bluefin_perpetual: &BluefinPerpetual,
//     // bluefin_bank: &mut BluefinBank<USDC>,
//     // bluefin_sequencer: &mut BluefinSequencer,
//     // vault: &mut Vault<USDC>,
//     // coin: &mut Coin<USDC>,
//     // amount: u64,
//     // receiver: address,
//     // ctx: &mut TxContext
//     //
//     txb.moveCall({
//       arguments: [
//         txb.object(this.getPerpetualID(vaultName)),
//         txb.object(this.deployment.BluefinBank),
//         txb.object(this.deployment.BluefinSequencer),
//         txb.object(vault),
//         txb.object(coinID),
//         txb.pure(toBigNumberStr(amount, USDC_DECIMALS)), // USDC amount is in 6 decimal places
//         txb.pure(receiver),
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.Package}::bluefin_vault::deposit_to_vault`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   async depositToBluefinBank(
//     vaultName: string,
//     amount: BigNumberable,
//     options?: {
//       coinId?: string;
//     },
//   ): Promise<SuiTransactionBlockResponse> {
//     let coinID = options?.coinId;
//     // if no coin id is provided, search for the coin that user holds
//     // having balance >= amount
//     if (!coinID) {
//       try {
//         coinID = (await this.getUSDCoinHavingBalance(amount)).coinObjectId;
//       } catch (e) {
//         console.log(e);
//         throw new Error("Couldn't fetch coin with enough amount");
//       }
//     }
//
//     const vault = this.getVaultID(vaultName);
//     console.log(`Vault ID: ${vault}`);
//
//     const bankAccount = await this.getVaultBankAccount(vaultName);
//     console.log(`Depositing to bank account address: ${bankAccount}`);
//
//     // TODO: generate tx hash each time somehow
//     const txHash =
//       "0x77e7f3d3e33c7aecbb757afa253179f80ce47f97fdcb11b34dbd444f13f98c06";
//
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.BluefinBank),
//         txb.object(this.deployment.BluefinSequencer),
//         txb.pure(txHash),
//         txb.pure(bankAccount),
//         txb.pure(toBigNumberStr(amount, USDC_DECIMALS)), // USDC amount is in 6 decimal places
//         txb.object(coinID),
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.BluefinPackage}::margin_bank::deposit_to_bank`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   async createTxHash(): Promise<SuiTransactionBlockResponse> {
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [],
//       target: `${this.deployment.Package}::bluefin_vault::create_tx_hash`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows caller to move funds the bank account of a vault inside bluefin's margin bank
//    * into the vault to hold for people to come in and withdraw
//    * @param vaultName The name of the vault
//    */
//   async moveFundsFromBankToVault(
//     vaultName: string,
//   ): Promise<SuiTransactionBlockResponse> {
//     const vault = this.getVaultID(vaultName);
//
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.BluefinBank),
//         txb.object(this.deployment.BluefinVaultStore),
//         txb.object(this.deployment.BluefinSequencer),
//         txb.object(vault),
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.Package}::bluefin_vault::move_vault_balance_from_bank`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows caller to request withdraw their locked funds from provided vault
//    * @param vaultName the name of the vault (perpetual-name)
//    * @param amount the amount to add to withdrawable amount
//    * @returns SuiTransactionBlockResponse
//    */
//   async updateVaultWithdraw(
//     vaultName: string,
//     amount: BigNumberable,
//   ): Promise<SuiTransactionBlockResponse> {
//     const vault = this.getVaultID(vaultName);
//
//     const txb = new TransactionBlock();
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.AdminCap),
//         txb.object(vault),
//         txb.pure(toBigNumberStr(amount, 0)), // shares are in 6 decimal place
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.Package}::bluefin_vault::update_vault_funds_to_be_withdrawn`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//   /**
//    * Allows caller to request withdraw their locked funds from provided vault
//    * @param vaultName the name of the vault (perpetual-name)
//    * @param shares the amount of shares a user wants to withdraw
//    * @returns SuiTransactionBlockResponse
//    */
//   async withdrawFromVault(
//     vaultName: string,
//     shares: BigNumberable,
//   ): Promise<SuiTransactionBlockResponse> {
//     const vault = this.getVaultID(vaultName);
//
//     const txb = new TransactionBlock();
//     txb.moveCall({
//       arguments: [
//         txb.object(this.getPerpetualID(vaultName)),
//         txb.object(this.deployment.BluefinBank),
//         txb.object(vault),
//         txb.pure(toBigNumberStr(shares, USDC_DECIMALS)), // shares are in 6 decimal place
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.Package}::bluefin_vault::withdraw_from_vault`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows caller to claim withdrawn funds on a user's behalf
//    * @param vaultName the name of the vault from which funds are to be claimed
//    * @param amount optional para, if not provided zero will be passed, implying all pending withdrawn funds will be claimed
//    * @param claimFor optional param, if not provided funds will be claimed for the caller
//    * @returns SuiTransactionBlockResponse
//    */
//   async claimFunds(
//     vaultName: string,
//     amount?: BigNumberable,
//     claimFor?: string,
//   ): Promise<SuiTransactionBlockResponse> {
//     const txb = new TransactionBlock();
//     txb.moveCall({
//       arguments: [
//         txb.object(this.getVaultID(vaultName)),
//         txb.pure(claimFor || this.signer.toSuiAddress()),
//         txb.pure(toBigNumberStr(amount || 0, USDC_DECIMALS)),
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.Package}::bluefin_vault::claim_withdrawn_funds`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows caller to claim rewards for the provided receiver from provided rewards pool
//    * @param payload The rewards payload consisting of
//    *    - pool The address of reward pool from which to claim rewards
//    *    - receiver The address for which to claim rewards
//    *    - amount The amount of rewards to be claimed (Must be in 1e9 Format that the signer signed on)
//    *    - nonce The unique nonce used by pool's operator to generate signature
//    * @param signature The signature created by pool's operator for provided payload
//    */
//   async claimRewards(
//     poolName: string,
//     payload: RewardsPayload,
//     signature: string,
//   ) {
//     const pool = this.getRewardsPool(poolName);
//
//     // serialize the payload data
//     const serPayload = bcs.ser("RewardSignaturePayload", payload).toBytes();
//
//     const txb = new TransactionBlock();
//     txb.moveCall({
//       arguments: [
//         txb.object(pool.id),
//         txb.pure(Array.from(serPayload)),
//         txb.pure(Array.from(hexStrToUint8(signature))),
//       ],
//       typeArguments: [pool.coin],
//       target: `${this.deployment.Package}::distributor::claim_rewards`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /**
//    * Allows admin to force withdraw funds for multiple users at once
//    * @param vaultName name of the vault(perpetual name ETH-PERP/BTC-PERP etc..)
//    * @param users array of user addresses to force withdraw for
//    * @param newPendingAmountsToWithdraw array of amounts to set as pending withdrawals for each user
//    * @returns SuiTransactionBlockResponse
//    */
//   async adminBatchForceWithdraw(
//     vaultName: string,
//     users: string[],
//     newPendingAmountsToWithdraw: string[],
//   ): Promise<SuiTransactionBlockResponse> {
//     const txb = new TransactionBlock();
//
//     txb.moveCall({
//       arguments: [
//         txb.object(this.deployment.AdminCap),
//         txb.object(this.getPerpetualID(vaultName)),
//         txb.object(this.deployment.BluefinBank),
//         txb.object(this.getVaultID(vaultName)),
//         txb.pure(users),
//         txb.pure(newPendingAmountsToWithdraw.map((amount) => amount)),
//       ],
//       typeArguments: [this.getSupportedCoin()],
//       target: `${this.deployment.Package}::bluefin_vault::admin_batch_force_withdraw`,
//     });
//
//     txb.setSender(this.signer.toSuiAddress());
//
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /// Returns a vault's bluefin bank account addrerss
//   async getVaultBankAccount(vaultName: string): Promise<number> {
//     const vaultID = this.getVaultID(vaultName);
//
//     const obj = await this.suiClient.getObject({
//       id: vaultID,
//       options: {
//         showContent: true,
//       },
//     });
//
//     const bankAccount = (obj.data?.content as any).fields.bank_account;
//
//     return bankAccount;
//   }
//
//   /// Returns a user's shares in provided vault
//   async getTotalShares(vaultName: string): Promise<number> {
//     const vaultID = this.getVaultID(vaultName);
//
//     const obj = await this.suiClient.getObject({
//       id: vaultID,
//       options: {
//         showContent: true,
//       },
//     });
//
//     const totalShares = (obj.data?.content as any).fields.total_shares;
//
//     return totalShares;
//   }
//
//   /// Returns a user's shares in provided vault
//   async getUserShares(vaultName: string, receiver?: string): Promise<any> {
//     const address = receiver || this.signer.toSuiAddress();
//     const vaultID = this.getVaultID(vaultName);
//
//     const obj = await this.suiClient.getObject({
//       id: vaultID,
//       options: {
//         showContent: true,
//       },
//     });
//
//     const userSharesMapID = (obj.data?.content as any).fields.user_shares.fields
//       .id.id;
//
//     try {
//       const shares = await this.suiClient.getDynamicFieldObject({
//         parentId: userSharesMapID,
//         name: {
//           type: "address",
//           value: address,
//         },
//       });
//
//       return {
//         converted: toBaseNumber((shares.data?.content as any).fields.value, 6),
//         notConverted: (shares.data?.content as any).fields.value,
//       };
//     } catch (e) {
//       return 0;
//     }
//   }
//
//   /// Returns the pending amount for claim that user had requested for withdraw
//   async getUserPendingWithdrawals(
//     vaultName: string,
//     user?: string,
//   ): Promise<number> {
//     const address = user || this.signer.toSuiAddress();
//     const vaultID = this.getVaultID(vaultName);
//
//     const obj = await this.suiClient.getObject({
//       id: vaultID,
//       options: {
//         showContent: true,
//       },
//     });
//
//     const usersPendingWithdrawalMapID = (obj.data?.content as any).fields
//       .user_pending_withdrawals.fields.id.id;
//
//     try {
//       const shares = await this.suiClient.getDynamicFieldObject({
//         parentId: usersPendingWithdrawalMapID,
//         name: {
//           type: "address",
//           value: address,
//         },
//       });
//
//       return toBaseNumber((shares.data?.content as any).fields.value, 6);
//     } catch (e) {
//       return 0;
//     }
//   }
//
//   /// Returns all coins a user hold of provided type
//   async getAllCoins(
//     address?: string,
//     coinType?: string,
//   ): Promise<PaginatedCoins> {
//     const coins = await this.suiClient.getCoins({
//       owner: address || this.signer.getPublicKey().toSuiAddress(),
//       coinType: coinType || this.getSupportedCoin(),
//     });
//     return coins;
//   }
//
//   async getClaimed(rewardsPool: string, nonce: string) {
//     const rewardsPoolId = this.getRewardsPool(rewardsPool)["id"];
//
//     const obj = await this.suiClient.getObject({
//       id: rewardsPoolId,
//       options: {
//         showContent: true,
//       },
//     });
//
//     console.log(obj);
//     const claimedID = (obj.data?.content as any).fields.claimed.fields.id.id;
//     console.log(claimedID);
//
//     try {
//       const res = await this.suiClient.getDynamicFieldObject({
//         parentId: claimedID,
//         name: {
//           type: "u128",
//           value: nonce,
//         },
//       });
//
//       return res;
//     } catch (e) {
//       console.log(e);
//       return 0;
//     }
//   }
//
//   /// Returns the coin having balance >= provided amount
//   async getUSDCoinHavingBalance(
//     amount: BigNumberable,
//     address?: string,
//   ): Promise<CoinStruct> {
//     address = address || this.signer.getPublicKey().toSuiAddress();
//     // get all usdc coins
//     const coins = await this.getAllCoins();
//
//     for (const coin of coins.data) {
//       try {
//         if (
//           new BigNumber(coin.balance).gte(toBigNumber(amount, USDC_DECIMALS))
//         ) {
//           return coin;
//         }
//       } catch (e) {
//         console.log(e);
//       }
//     }
//
//     throw `User ${address} has no USD coin having balance: ${+amount}`;
//   }
//
//   /// Returns the coin having balance == provided amount
//   async getCoinWithExactBalance(
//     amount: BigNumberable,
//     coinType: string,
//     address?: string,
//   ): Promise<CoinStruct> {
//     address = address || this.signer.getPublicKey().toSuiAddress();
//     // get all usdc coins
//     const coins = await this.getAllCoins(address, coinType);
//
//     for (const coin of coins.data) {
//       if (new BigNumber(coin.balance).eq(toBigNumber(amount, TOKEN_DECIMALS))) {
//         return coin;
//       }
//     }
//
//     throw `User ${address} has no coin having exact balance: ${+amount}`;
//   }
//
//   /// Returns the balance of user (in base number, removes extra decimals) for provided coin
//   /// The default coin is USDC
//   async getCoinBalance(
//     address?: string,
//     coinType?: string,
//     decimals = USDC_DECIMALS,
//   ): Promise<number> {
//     const coins = await this.getAllCoins(address, coinType);
//     const bal = coins.data.reduce(
//       (total: number, coin: any) => total + +coin.balance,
//       0,
//     );
//
//     return toBaseNumber(bal, decimals);
//   }
//
//   /// Spits the coins
//   async splitCoin(
//     amount: BigNumberable,
//     coinType: string,
//   ): Promise<SuiTransactionBlockResponse> {
//     const txb = new TransactionBlock();
//     const coins = await this.getAllCoins(this.signer.toSuiAddress(), coinType);
//
//     if (coins.data.length == 0) {
//       throw "No coins available to split";
//     }
//
//     let coin;
//
//     if (
//       coinType ==
//       "0x0000000000000000000000000000000000000000000000000000000000000002::sui::SUI"
//     ) {
//       coin = txb.splitCoins(txb.gas, [
//         txb.pure(toBigNumberStr(amount, TOKEN_DECIMALS)),
//       ]);
//     } else {
//       coin = txb.splitCoins(coins.data[0].coinObjectId, [
//         txb.pure(toBigNumberStr(amount, TOKEN_DECIMALS)),
//       ]);
//     }
//
//     txb.transferObjects([coin], this.signer.toSuiAddress());
//
//     txb.setSender(this.signer.toSuiAddress());
//     return Interactor.signAndExecuteTxBlock(txb, this.signer, this.suiClient);
//   }
//
//   /// Returns the available withdrawable balance in the bluefin bank
//   async getBluefinBankBalance(address?: string): Promise<number> {
//     address = address || this.signer.toSuiAddress();
//
//     const bankObj = await this.suiClient.getObject({
//       id: this.deployment.BluefinBank,
//       options: { showContent: true },
//     });
//
//     const bankTableID = (bankObj.data?.content as any).fields.accounts.fields.id
//       .id;
//
//     try {
//       const availableBalance = await this.suiClient.getDynamicFieldObject({
//         parentId: bankTableID,
//         name: {
//           type: "address",
//           value: address,
//         },
//       });
//
//       return toBaseNumber(
//         (availableBalance.data?.content as any).fields.value.fields.balance,
//         9,
//       );
//     } catch (e) {
//       return 0;
//     }
//   }
//
//   /// formulates the supported coin type, to be passed as `typeArguments` to contract calls
//   getSupportedCoin(): string {
//     return `${this.deployment.SupportedCoin}::coin::COIN`;
//   }
//
//   getVaultID(vaultName: string) {
//     return this.deployment.Vaults[vaultName]["id"];
//   }
//
//   getPerpetualID(perpName: string) {
//     return this.deployment.BluefinPerpetuals[perpName];
//   }
//
//   getVaultAccount(vaultName: string) {
//     return this.deployment.Vaults[vaultName]["account"];
//   }
//
//   getRewardsPool(poolName: string): RewardPool {
//     return this.deployment.RewardPools[poolName];
//   }
// }
