// SPDX-License-Identifier: MIT
//
// Tests for MolePinBridgeGateway (V3): fee math ($1 worth of native), fee cap ($5),
// oracle safety (zero price reverts), destination allowlist, treasury update,
// and owner-only access control.
//
// V3 change: gateway constructor is (owner, treasury); mol/router/feed are injected
// via configure(mol, router, feed) after deploy. bridge() is (selector, recipient, amount).
//
// 게이트웨이 테스트(V3): 수수료 수학($1어치 native), 상한($5), 오라클 안전(0 가격
// revert), 도착 체인 화이트리스트, treasury 갱신, owner 권한.

import { expect } from "chai";
import { network } from "hardhat";
import { parseEther } from "viem";

const SAMPLE_SELECTOR = 13264668187771770619n;
const BNB_PRICE_8DEC = 85_100_000_000n; // $851, 8 decimals
const CCIP_FEE = parseEther("0.0002"); // mock CCIP fee in native

describe("MolePinBridgeGateway", () => {
  let viem: any;
  let owner: any;
  let treasury: any;
  let user: any;

  before(async () => {
    const conn = await network.getOrCreate();
    viem = conn.viem;
    [owner, treasury, user] = await viem.getWalletClients();
  });

  async function deployAll() {
    const feed = await viem.deployContract("MockPriceOracle", [8, BNB_PRICE_8DEC]);
    const router = await viem.deployContract("MockCCIPRouter", [CCIP_FEE]);
    const mol = await viem.deployContract("MolePin", [owner.account.address]);
    // V3: 2-arg constructor (owner, treasury)
    const gw = await viem.deployContract("MolePinBridgeGateway", [
      owner.account.address,
      treasury.account.address,
    ]);
    // V3: inject mol/router/feed via configure
    await gw.write.configure([mol.address, router.address, feed.address]);
    return { feed, router, mol, gw };
  }

  // ── Fee math ──────────────────────────────────────────────────────────────
  it("computes molepinFeeInNative as $1 worth of native (BNB $851)", async () => {
    const { gw } = await deployAll();
    const fee = await gw.read.molepinFeeInNative();
    const expected = (parseEther("1") * 10n ** 8n) / BNB_PRICE_8DEC;
    expect(fee).to.equal(expected);
    const backToUsd = (fee * BNB_PRICE_8DEC) / 10n ** 8n;
    expect(backToUsd >= parseEther("0.999") && backToUsd <= parseEther("1.001")).to.equal(true);
  });

  it("fee scales correctly when price changes (BNB $1000)", async () => {
    const { gw, feed } = await deployAll();
    await feed.write.setAnswer([100_000_000_000n]); // $1000
    expect(await gw.read.molepinFeeInNative()).to.equal(parseEther("0.001"));
  });

  // ── Fee cap ─────────────────────────────────────────────────────────────
  it("allows setFeeUsd up to the $5 cap", async () => {
    const { gw } = await deployAll();
    await gw.write.setFeeUsd([parseEther("5")]);
    expect(await gw.read.feeUsd()).to.equal(parseEther("5"));
  });

  it("rejects setFeeUsd above the $5 cap", async () => {
    const { gw } = await deployAll();
    await viem.assertions.revert(gw.write.setFeeUsd([parseEther("6")]));
  });

  it("default fee is $1", async () => {
    const { gw } = await deployAll();
    expect(await gw.read.feeUsd()).to.equal(parseEther("1"));
  });

  // ── Oracle safety ─────────────────────────────────────────────────────────
  it("reverts when oracle price is zero", async () => {
    const { gw, feed } = await deployAll();
    await feed.write.setAnswer([0n]);
    await viem.assertions.revert(gw.read.molepinFeeInNative());
  });

  it("reverts when oracle price is stale (older than 1h)", async () => {
    const { gw, feed } = await deployAll();
    await feed.write.setUpdatedAt([1000n]);
    await viem.assertions.revert(gw.read.molepinFeeInNative());
  });

  it("handles an 18-decimal feed correctly", async () => {
    const feed18 = await viem.deployContract("MockPriceOracle", [18, 2n * 10n ** 18n]); // $2, 18dec
    const router = await viem.deployContract("MockCCIPRouter", [CCIP_FEE]);
    const mol = await viem.deployContract("MolePin", [owner.account.address]);
    const gw = await viem.deployContract("MolePinBridgeGateway", [
      owner.account.address,
      treasury.account.address,
    ]);
    await gw.write.configure([mol.address, router.address, feed18.address]);
    // $1 / $2 = 0.5 token (18dec)
    expect(await gw.read.molepinFeeInNative()).to.equal(parseEther("0.5"));
  });

  // ── Destination allowlist ─────────────────────────────────────────────────
  it("rejects bridge to a non-allowed destination", async () => {
    const { gw, mol } = await deployAll();
    const amount = 1000n * 10n ** 18n;
    await mol.write.approve([gw.address, amount]);
    // V3 bridge: (selector, recipient, amount). 999 not allowed → revert.
    await viem.assertions.revert(
      gw.write.bridge([999n, owner.account.address, amount], { value: parseEther("1") }),
    );
  });

  it("owner can allow a destination chain", async () => {
    const { gw } = await deployAll();
    await gw.write.setDestChain([SAMPLE_SELECTOR, true]);
    expect(await gw.read.allowedDestChains([SAMPLE_SELECTOR])).to.equal(true);
  });

  // ── Trusted remote gateway (V3) ────────────────────────────────────────────
  it("owner can set a trusted remote gateway", async () => {
    const { gw } = await deployAll();
    await gw.write.setTrustedRemoteGateway([SAMPLE_SELECTOR, gw.address]);
    expect((await gw.read.trustedRemoteGateway([SAMPLE_SELECTOR])).toLowerCase()).to.equal(
      gw.address.toLowerCase(),
    );
  });

  it("default destGasLimit is 250000", async () => {
    const { gw } = await deployAll();
    expect(await gw.read.destGasLimit()).to.equal(250_000n);
  });

  // ── Access control ────────────────────────────────────────────────────────
  it("setFeeUsd is owner-only (reverts with OwnableUnauthorizedAccount)", async () => {
    const { gw } = await deployAll();
    const gwAsUser = await viem.getContractAt("MolePinBridgeGateway", gw.address, {
      client: { wallet: user },
    });
    await viem.assertions.revertWithCustomError(
      gwAsUser.write.setFeeUsd([parseEther("2")]),
      gw,
      "OwnableUnauthorizedAccount",
    );
  });

  it("setTreasury is owner-only and updates", async () => {
    const { gw } = await deployAll();
    await gw.write.setTreasury([user.account.address]);
    expect((await gw.read.treasury()).toLowerCase()).to.equal(user.account.address.toLowerCase());
  });

  // ── configure guard (V3) ────────────────────────────────────────────────────
  it("configure can only be called once", async () => {
    const { gw, mol, router, feed } = await deployAll();
    await viem.assertions.revert(
      gw.write.configure([mol.address, router.address, feed.address]),
    );
  });
});