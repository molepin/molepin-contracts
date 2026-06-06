// SPDX-License-Identifier: MIT
//
// Tests for the MolePin home token: fixed supply, no mint, voluntary burn,
// and ERC20 basics. Verifies the immutability guarantees the token promises.
//
// MolePin 홈 토큰 테스트: 고정 발행량, mint 없음, 자발적 burn, ERC20 기본.
// 토큰이 약속한 불변성 보장을 검증한다.

import { expect } from "chai";
import { network } from "hardhat";

const GENESIS = 6_942_420_888_888n * 10n ** 18n;

describe("MolePin (home token)", () => {
  let viem: any;
  let owner: any;
  let other: any;

  before(async () => {
    const conn = await network.getOrCreate();
    viem = conn.viem;
    [owner, other] = await viem.getWalletClients();
  });

  async function deploy() {
    return viem.deployContract("MolePin", [owner.account.address]);
  }

  it("mints the exact genesis supply to the initial owner", async () => {
    const mol = await deploy();
    expect(await mol.read.totalSupply()).to.equal(GENESIS);
    expect(await mol.read.balanceOf([owner.account.address])).to.equal(GENESIS);
  });

  it("has 18 decimals and correct name/symbol", async () => {
    const mol = await deploy();
    expect(await mol.read.decimals()).to.equal(18);
    expect(await mol.read.name()).to.equal("MolePin");
    expect(await mol.read.symbol()).to.equal("MOL");
  });

  it("exposes GENESIS_SUPPLY as the permanent max", async () => {
    const mol = await deploy();
    expect(await mol.read.GENESIS_SUPPLY()).to.equal(GENESIS);
  });

  it("has NO mint function (cannot increase supply)", async () => {
    const mol = await deploy();
    const hasMint = mol.abi.some((x: any) => x.type === "function" && x.name === "mint");
    expect(hasMint, "mint must not exist on the home token").to.equal(false);
  });

  it("allows voluntary burn of own balance and reduces supply", async () => {
    const mol = await deploy();
    const burnAmount = 1_000n * 10n ** 18n;
    await mol.write.burn([burnAmount]);
    expect(await mol.read.totalSupply()).to.equal(GENESIS - burnAmount);
  });

  it("transfers normally with no fee (pure ERC20)", async () => {
    const mol = await deploy();
    const amount = 5_000n * 10n ** 18n;
    await mol.write.transfer([other.account.address, amount]);
    expect(await mol.read.balanceOf([other.account.address])).to.equal(amount);
  });

  it("has no blacklist / pause functions", async () => {
    const mol = await deploy();
    const names = mol.abi.filter((x: any) => x.type === "function").map((f: any) => f.name);
    for (const forbidden of ["blacklist", "pause", "unpause", "setBlacklist"]) {
      expect(names.includes(forbidden), `${forbidden} must not exist`).to.equal(false);
    }
  });
});