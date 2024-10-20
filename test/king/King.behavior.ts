import { expect, assert } from "chai";
import hre from "hardhat";

export function shouldInitiateGame(): void {
  it("should initiage game with default values", async function () {
    // test initial value
    let playersCount = await this.king.getPlayerCount();
    expect(Number(playersCount)).to.be.equal(1);

    let currentWeather = await this.king.getCurrentWeather();
    expect(Number(currentWeather)).to.be.equal(0);

    let currentKing = await this.king.getCurrentKing();
    expect(currentKing).to.be.equal(this.signers.admin.address);
  });

}
