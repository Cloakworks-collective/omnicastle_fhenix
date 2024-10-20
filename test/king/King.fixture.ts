import type { KingOfTheCastle } from "../../types";
import axios from "axios";
import hre from "hardhat";

export async function deployCounterFixture(): Promise<{
  king: KingOfTheCastle;
  address: string;
}> {
  const accounts = await hre.ethers.getSigners();
  const contractOwner = accounts[0];

  const King = await hre.ethers.getContractFactory("KingOfTheCastle");
  const king = await King.connect(contractOwner).deploy();
  await king.waitForDeployment();
  const address = await king.getAddress();
  return { king, address };
}

export async function getTokensFromFaucet() {
  if (hre.network.name === "localfhenix") {
    const signers = await hre.ethers.getSigners();

    if (
      (await hre.ethers.provider.getBalance(signers[0].address)).toString() ===
      "0"
    ) {
      await hre.fhenixjs.getFunds(signers[0].address);
    }
  }
}