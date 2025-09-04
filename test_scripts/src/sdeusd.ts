import { DeUSDMintingManager, OrderType } from "./deusd-minting";

const NETWORK = process.env.NETWORK as string;
const PRIVATE_KEY = process.env.PRIVATE_KEY as string;
const PACKAGE_ADDRESS = process.env.PACKAGE_ADDRESS as string;
const GLOBAL_CONFIG_ID = process.env.GLOBAL_CONFIG_ID as string;
const DEUSD_MINTING_MANAGEMENT_ID = process.env
  .DEUSD_MINTING_MANAGEMENT_ID as string;
const SDEUSD_MANAGEMENT_ID = process.env.SDEUSD_MANAGEMENT_ID as string;
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
    const user =
      "0xc3a73e4ea73a30baabb4959bbf74dd3a7fd5cea6ce17bee3bc39717adbe60a2f";
    const userCooldown = await deusdMintingManager.getUserCooldown(
      SDEUSD_MANAGEMENT_ID,
      user,
    );
    console.log(userCooldown);
  } catch (error) {
    console.log("error", error);
  }
}

main();
