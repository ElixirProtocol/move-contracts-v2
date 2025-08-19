import { Transaction } from "@mysten/sui/transactions";
import { ENV, SUI_CLIENT, getKeyPairFromPvtKey } from "./helpers/utils";
import { bcs } from "@mysten/bcs";

const client = SUI_CLIENT;
async function hashOrder(
  collateralType: string,
  orderType: number,
  expiry: bigint,
  nonce: bigint,
  benefactor: string,
  beneficiary: string,
  collateralAmount: bigint,
  deusdAmount: bigint,
): Promise<Uint8Array> {
  console.log("Calling on-chain view function `hash_order`...");

  const tx = new Transaction();
  tx.moveCall({
    target: `0xd3d9fa3b654479e9cf8c9d63fad475a4ec70efb5bf310de94908ea227ee3afaf::deusd_minting::hash_order`,
    typeArguments: [collateralType],
    arguments: [
      tx.object(
        "0xf6273fe16893af00b06f5f717f469ab8a8621509d5a814c64489ac96d87a62f2",
      ),
      tx.pure.u8(orderType),
      tx.pure.u64(expiry.toString()),
      tx.pure.u64(nonce.toString()),
      tx.pure.address(benefactor),
      tx.pure.address(beneficiary),
      tx.pure.u64(collateralAmount.toString()),
      tx.pure.u64(deusdAmount.toString()),
    ],
  });

  const sender =
    "0xc3a73e4ea73a30baabb4959bbf74dd3a7fd5cea6ce17bee3bc39717adbe60a2f";

  console.log("Simulating transaction with devInspectTransactionBlock...");
  const result = await client.devInspectTransactionBlock({
    sender: sender,
    transactionBlock: tx,
  });

  // 4. Parse the result.
  const returnValues = result.results?.[0]?.returnValues;
  console.log(returnValues);
  if (returnValues) {
    //@ts-ignore
    const rawBytes = returnValues[0][0]; //@ts-ignore

    // Parse the raw bytes using the BCS schema.
    const hashResult = bcs
      .byteVector()
      .serialize(new Uint8Array(rawBytes))
      .toBytes();
    return hashResult;
  }

  throw new Error("Failed to get order hash from on-chain function.");
}

async function main() {
  const benefactor = getKeyPairFromPvtKey(
    ENV.OWNER_KEY,
    ENV.OWNER_WALLET_SCHEME,
  );
  const ORDER_TYPE_MINT = 0;

  // Example order parameters
  const orderParams = {
    collateralType: "0x2::sui::SUI", // The generic type argument
    orderType: ORDER_TYPE_MINT,
    expiry: 1789000000n, // Use 'n' for BigInt
    nonce: 1n,
    benefactor:
      "0xc3a73e4ea73a30baabb4959bbf74dd3a7fd5cea6ce17bee3bc39717adbe60a2f", // Replace with a valid address
    beneficiary:
      "0xc3a73e4ea73a30baabb4959bbf74dd3a7fd5cea6ce17bee3bc39717adbe60a2f", // Replace with a valid address
    collateralAmount: 1n, // 1 SUI in MIST
    deusdAmount: 1000000000n,
  };

  const orderHash = await hashOrder(
    orderParams.collateralType,
    orderParams.orderType,
    orderParams.expiry,
    orderParams.nonce,
    orderParams.benefactor,
    orderParams.beneficiary,
    orderParams.collateralAmount,
    orderParams.deusdAmount,
  );
  console.log("Order hash");
  console.log(orderHash);

  const signature = await benefactor.sign(orderHash);
  console.log("Signature");
  console.log(signature);

  // const serializedSignature = bcs.en("vector<u8>", signature).toString("hex");
  // console.log(`Serialized Signature: ${serializedSignature}\n`);

  // de-serialize the signature content
  // const deSig = bcs.de("Signature", signature, "hex");
  // // get hex of the signature
  // const hexSig = Buffer.from(deSig.sig).toString("hex");
  // // extract signer's public key
  // const pk = Uint8Array.from(deSig.pk);
  // // verify that the signature is valid
  // const isSigValid = Signer.verify(signature, order_hash);
  //
  // console.log(`Is signature valid: ${isSigValid}\n`);
}

main();
