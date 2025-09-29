import { DeUSDMintingManager, OrderType } from "./deusd-minting";

const NETWORK = process.env.NETWORK as string;
const PRIVATE_KEY = process.env.PRIVATE_KEY as string;
const PACKAGE_ADDRESS = process.env.PACKAGE_ADDRESS as string;
const GLOBAL_CONFIG_ID = process.env.GLOBAL_CONFIG_ID as string;
const DEUSD_MINTING_MANAGEMENT_ID = process.env
  .DEUSD_MINTING_MANAGEMENT_ID as string;
const DEUSD_CONFIG_ID = process.env.DEUSD_CONFIG_ID as string;
const LOCKED_FUNDS_MANAGEMENT_ID = process.env
  .LOCKED_FUNDS_MANAGEMENT_ID as string;
const BENEFACTOR_ADDRESS = process.env.BENEFACTOR_ADDRESS as string;
const COLLATERAL_TYPE = process.env.COLLATERAL_TYPE as string;

async function main() {
  const deusdMintingManager = new DeUSDMintingManager(
    NETWORK as "mainnet" | "testnet",
    PACKAGE_ADDRESS,
    PRIVATE_KEY,
  );

  try {
    const mintOrderResult = await deusdMintingManager.mint(
      DEUSD_MINTING_MANAGEMENT_ID,
      LOCKED_FUNDS_MANAGEMENT_ID,
      DEUSD_CONFIG_ID,
      GLOBAL_CONFIG_ID,
      {
        orderType: OrderType.MINT,
        expiry: BigInt(Math.floor(Date.now() / 1000) + 60 * 10), // 10 minutes from now
        nonce: BigInt(4), // update nonce with each request
        benefactor: BENEFACTOR_ADDRESS,
        beneficiary: BENEFACTOR_ADDRESS, // use same address as BENEFACTOR_ADDRESS for testing
        collateralType: COLLATERAL_TYPE,
        collateralAmount: BigInt(5000000),
        deusdAmount: BigInt(5000000),
      },
      {
        addresses: [BENEFACTOR_ADDRESS],
        ratios: ["10000"],
      },
    );
    console.log("Mint order result:", mintOrderResult);
  } catch (error) {
    console.log("error", error);
  }
}

main();
