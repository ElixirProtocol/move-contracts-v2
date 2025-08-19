import { config } from "dotenv";
import fs from "fs";
import type { SignatureScheme } from "@mysten/sui/cryptography";
import { Keypair } from "@mysten/sui/cryptography";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Secp256k1Keypair } from "@mysten/sui/keypairs/secp256k1";
import type {
  CoinStruct,
  PaginatedCoins,
  SuiEvent,
  SuiObjectChange,
  SuiTransactionBlockResponse,
  SuiTransactionBlockResponseOptions,
} from "@mysten/sui/client";
import { SuiClient } from "@mysten/sui/client";
import BigNumber from "bignumber.js";

config({ path: ".env" });

export const ENV = {
  DEPLOY_ON: process.env.DEPLOY_ON as DeployOn,
  DEPLOYER_KEY: process.env.DEPLOYER_KEY || "0x",
  DEPLOYER_SEED: process.env.DEPLOYER_SEED || "0x",

  // defaults wallet scheme to secp256k1
  WALLET_SCHEME: (process.env.WALLET_SCHEME || "Secp256k1") as SignatureScheme,

  OWNER_KEY: process.env.OWNER_KEY || "0x",
  OWNER_WALLET_SCHEME: (process.env.OWNER_WALLET_SCHEME ||
    "Secp256k1") as SignatureScheme,
  MULTISIG_KEY_1: process.env.MULTISIG_KEY_1 || "0x",
  MULTISIG_1_WALLET_SCHEME: (process.env.MULTISIG_1_WALLET_SCHEME ||
    "Secp256k1") as SignatureScheme,
  MULTISIG_KEY_2: process.env.MULTISIG_KEY_2 || "0x",
  MULTISIG_2_WALLET_SCHEME: (process.env.MULTISIG_2_WALLET_SCHEME ||
    "Secp256k1") as SignatureScheme,
};

export const CONFIG = JSON.parse(fs.readFileSync("./config.json", "utf8"))[
  ENV.DEPLOY_ON
];

export const SUI_CLIENT = new SuiClient({
  url: CONFIG.rpc,
});

// Decimals used by SUI and BLUE coin
export const TOKEN_DECIMALS = 9;

// Decimals used by USDC coin
export const USDC_DECIMALS = 6;

export async function sleep(timeInMs: number) {
  await new Promise((resolve) => setTimeout(resolve, timeInMs));
}

/// converts private key into KeyPair
export function getKeyPairFromPvtKey(
  key: string,
  scheme: SignatureScheme = "Secp256k1",
): Keypair {
  if (key.startsWith("0x")) {
    key = key.substring(2); // Remove the first two characters (0x)
  }
  switch (scheme) {
    case "ED25519":
      return Ed25519Keypair.fromSecretKey(Buffer.from(key, "hex"));
    case "Secp256k1":
      return Secp256k1Keypair.fromSecretKey(Buffer.from(key, "hex"));
    default:
      throw new Error("Provided key is invalid");
  }
}

export interface ObjectsMap {
  [object: string]: string;
}

export interface RewardPool {
  id: string;
  coin: string;
}

export type BigNumberable = BigNumber | number | string;

export type DeployOn = "mainnet" | "testnet" | "localnet";

export function toBigNumber(val: BigNumberable, base: number): BigNumber {
  return new BigNumber(val).multipliedBy(new BigNumber(1).shiftedBy(base));
}

export function toBigNumberStr(val: BigNumberable, base: number): string {
  return toBigNumber(val, base).toFixed(0);
}

export function toBaseNumber(
  val: BigNumberable,
  base: number,
  decimals = 3,
): number {
  return Number(new BigNumber(val).shiftedBy(-base).toFixed(decimals));
}

export function getEvent(
  txResponse: SuiTransactionBlockResponse,
  eventName: string,
): SuiEvent[] {
  const events = [];
  for (const event of txResponse.events || []) {
    if (event.type.endsWith(eventName)) events.push(event);
  }

  return events;
}

export function getCreatedObjectsIDs(
  txResponse: SuiTransactionBlockResponse,
): ObjectsMap {
  const objects: ObjectsMap = {};

  for (const object of txResponse.objectChanges as SuiObjectChange[]) {
    if (object.type == "mutated") continue;
    // only Packages get published
    if (object.type == "published") {
      objects["Package"] = object.packageId;
    } else if (object.type == "created") {
      const type = (
        object.objectType.match(
          /^(?<pkg>[\w]+)::(?<mod>[\w]+)::(?<type>[\w]+)$/,
        )?.groups as any
      )["type"];

      objects[type] = object.objectId;
    }
  }

  return objects;
}

export function readJSONFile(filePath: string) {
  return fs.existsSync(filePath)
    ? JSON.parse(fs.readFileSync(filePath).toString())
    : {};
}

export function writeJSONFile(filePath: string, content: JSON) {
  fs.writeFileSync(filePath, JSON.stringify(content));
}

export function hexStrToUint8(data: string): Uint8Array {
  return Uint8Array.from(
    data.match(/.{1,2}/g)?.map((byte) => parseInt(byte, 16)) || [],
  );
}
