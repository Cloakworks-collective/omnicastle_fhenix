import { createPermitForContract } from "../../utils/instance";
import type { Signers } from "../types";
import { shouldInitiateGame } from "./King.behavior";
import { deployCounterFixture, getTokensFromFaucet } from "./King.fixture";
import hre from "hardhat";

describe("Unit tests", function () {
  before(async function () {
    this.signers = {} as Signers;

    // get tokens from faucet if we're on localfhenix and don't have a balance
    await getTokensFromFaucet();

    const { king, address } = await deployCounterFixture();
    this.king = king;

    // initiate fhenixjs
    this.permission = await createPermitForContract(hre, address);
    this.fhenixjs = hre.fhenixjs;

    // set admin account/signer
    const signers = await hre.ethers.getSigners();
    this.signers.admin = signers[0];
  });

  describe("King Of the Castle", function () {
    shouldInitiateGame();
  });

});
