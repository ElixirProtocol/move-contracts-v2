import { getFullnodeUrl, SuiClient } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { bcs } from "@mysten/sui/bcs";
import { normalizeSuiAddress } from "@mysten/sui/utils";
import { keccak_256 } from "@noble/hashes/sha3";
import { getStructTypeString, parseStructType } from "./utils";

export enum OrderType {
  MINT = 0,
  REDEEM = 1,
}

export interface Order {
  orderType: OrderType;
  expiry: bigint;
  nonce: bigint;
  benefactor: string;
  beneficiary: string;
  collateralType: string; // type of the collateral asset, e.g. "0x2::sui::SUI"
  collateralAmount: bigint;
  deusdAmount: bigint;
}

export interface RouteConfig {
  addresses: string[];
  ratios: string[];
}

const ORDER_DOMAIN_SEPARATOR = "deusd_order";

export class DeUSDMintingManager {
  private client: SuiClient;
  private packageId: string;
  private domainSeparator: Uint8Array;
  private keypair?: Ed25519Keypair;

  constructor(
    network: "mainnet" | "testnet",
    packageId: string,
    privateKey?: string
  ) {
    this.client = new SuiClient({ url: getFullnodeUrl(network) });
    this.packageId = packageId;
    this.domainSeparator = this.calculateDomainSeparator();

    if (privateKey) {
      this.keypair = Ed25519Keypair.fromSecretKey(privateKey);
    }
  }

  async mint(
    managementId: string,
    lockedFundsManagementId: string,
    deusdManagementId: string,
    globalConfigId: string,
    order: Order,
    route: RouteConfig
  ): Promise<any> {
    if (!this.keypair) {
      throw new Error("Keypair not provided");
    }

    const tx = new Transaction();
    const clockId = "0x6"; // System clock object ID

    const publicKey = this.keypair.getPublicKey().toRawBytes();
    const orderSignature = await this.getOrderSignature(order);

    tx.moveCall({
      target: `${this.packageId}::deusd_minting::mint`,
      typeArguments: [order.collateralType],
      arguments: [
        tx.object(managementId),
        tx.object(lockedFundsManagementId),
        tx.object(deusdManagementId),
        tx.object(globalConfigId),
        tx.pure.u64(order.expiry),
        tx.pure.u64(order.nonce),
        tx.pure.address(order.benefactor),
        tx.pure.address(order.beneficiary),
        tx.pure.u64(order.collateralAmount),
        tx.pure.u64(order.deusdAmount),
        tx.pure.vector("address", route.addresses),
        tx.pure.vector("u64", route.ratios),
        tx.pure.vector("u8", publicKey),
        tx.pure.vector("u8", orderSignature),
        tx.object(clockId),
      ],
    });

    return this.client.signAndExecuteTransaction({
      transaction: tx,
      signer: this.keypair,
      options: {
        showEffects: true,
        showEvents: true,
      },
    });
  }

  calculateDomainSeparator(): Uint8Array {
    const addressBytes = bcs.Address.serialize(
      normalizeSuiAddress(this.packageId)
    ).toBytes();
    let data = Buffer.from("deusd_minting", "ascii");
    data = Buffer.concat([addressBytes, data]);
    return keccak_256(data);
  }

  getOrderSignature(order: Order): Promise<Uint8Array> {
    const orderHash = this.hashOrder(order);
    if (!this.keypair) {
      throw new Error("Keypair not provided");
    }

    return this.keypair.sign(orderHash);
  }

  hashOrder(order: Order): Uint8Array {
    const data: Uint8Array[] = [];

    data.push(this.domainSeparator);

    // "deusd_order" as ASCII bytes
    const orderLabelBytes = Buffer.from(ORDER_DOMAIN_SEPARATOR, "ascii");

    data.push(orderLabelBytes);
    data.push(bcs.U8.serialize(order.orderType).toBytes());
    data.push(bcs.U64.serialize(order.expiry).toBytes());
    data.push(bcs.U64.serialize(order.nonce).toBytes());
    data.push(
      bcs.Address.serialize(normalizeSuiAddress(order.benefactor)).toBytes()
    );
    data.push(
      bcs.Address.serialize(normalizeSuiAddress(order.beneficiary)).toBytes()
    );

    // struct tag string (type_name::get<T>())
    const collateralType = Buffer.from(
      getStructTypeString(parseStructType(order.collateralType)),
      "ascii"
    );
    data.push(
      bcs.vector(bcs.U8).serialize(Array.from(collateralType)).toBytes()
    );

    data.push(bcs.U64.serialize(order.collateralAmount).toBytes());
    data.push(bcs.U64.serialize(order.deusdAmount).toBytes());

    const allBytes = Buffer.concat(data);
    return keccak_256(allBytes);
  }
}
