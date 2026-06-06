// SPDX-License-Identifier: MIT
//
// Integration tests for the full bridge() flow: MOL pull + router forwarding,
// MolePin fee routed to treasury (in native), excess native refunded, event
// emission, and the insufficient-native revert. Uses MockCCIPRouter so the
// native flow is exercised without a real CCIP lane.
//
// bridge() 전체 흐름 통합 테스트: MOL 회수+라우터 전달, MolePin 수수료의
// treasury 전달(native), 초과 native 환불, 이벤트, native 부족 revert.
// MockCCIPRouter로 실제 CCIP lane 없이 native 흐름을 검증한다.

import { expect } from "chai";
import { network } from "hardhat";
import { parseEther } from "viem";

const SELECTOR = 13264668187771770619n;
const BNB_PRICE_8DEC = 85_100_000_000n; // $851
const CCIP_FEE = parseEther("0.0002");

describe("MolePinBridgeGateway — bridge() integration", () => {
  let viem: any;
  let pub: any;
  let owner: any;
  let treasury: any;
  let user: any;

  before(async () => {
    const conn = await network.getOrCreate();
    viem = conn.viem;
    pub = await viem.getPublicClient();
    [owner, treasury, user] = await viem.getWalletClients();
  });

  async function setup() {
    const feed = await viem.deployContract("MockPriceOracle", [8, BNB_PRICE_8DEC]);
    const router = await viem.deployContract("MockCCIPRouter", [CCIP_FEE]);
    const mol = await viem.deployContract("MolePin", [owner.account.address]);
    const gw = await viem.deployContract("MolePinBridgeGateway", [
      owner.account.address,
      mol.address,
      router.address,
      feed.address,
      treasury.account.address,
    ]);
    await gw.write.setDestChain([SELECTOR, true]);
    // fund the user with MOL so they can bridge
    const amount = 1_000_000n * 10n ** 18n;
    await mol.write.transfer([user.account.address, amount]);
    return { feed, router, mol, gw, amount };
  }

  it("routes the MolePin fee (native) to the treasury", async () => {
    const { mol, gw } = await setup();
    const molepinFee = await gw.read.molepinFeeInNative();
    const total = molepinFee + CCIP_FEE;
    const bridgeAmt = 1000n * 10n ** 18n;

    const molUser = await viem.getContractAt("MolePin", mol.address, { client: { wallet: user } });
    await molUser.write.approve([gw.address, bridgeAmt]);
    const gwUser = await viem.getContractAt("MolePinBridgeGateway", gw.address, {
      client: { wallet: user },
    });

    const before = await pub.getBalance({ address: treasury.account.address });
    await gwUser.write.bridge([SELECTOR, user.account.address, bridgeAmt, "0x"], { value: total });
    const after = await pub.getBalance({ address: treasury.account.address });

    expect(after - before).to.equal(molepinFee, "treasury should receive exactly the MolePin fee");
  });

  it("emits BridgeInitiated", async () => {
    const { mol, gw } = await setup();
    const total = (await gw.read.molepinFeeInNative()) + CCIP_FEE;
    const bridgeAmt = 1000n * 10n ** 18n;
    const molUser = await viem.getContractAt("MolePin", mol.address, { client: { wallet: user } });
    await molUser.write.approve([gw.address, bridgeAmt]);
    const gwUser = await viem.getContractAt("MolePinBridgeGateway", gw.address, {
      client: { wallet: user },
    });
    await viem.assertions.emit(
      gwUser.write.bridge([SELECTOR, user.account.address, bridgeAmt, "0x"], { value: total }),
      gw,
      "BridgeInitiated",
    );
  });

  it("refunds excess native to the sender", async () => {
    const { mol, gw } = await setup();
    const molepinFee = await gw.read.molepinFeeInNative();
    const exact = molepinFee + CCIP_FEE;
    const overpay = exact + parseEther("0.5"); // 0.5 BNB too much
    const bridgeAmt = 1000n * 10n ** 18n;

    const molUser = await viem.getContractAt("MolePin", mol.address, { client: { wallet: user } });
    await molUser.write.approve([gw.address, bridgeAmt]);
    const gwUser = await viem.getContractAt("MolePinBridgeGateway", gw.address, {
      client: { wallet: user },
    });

    const before = await pub.getBalance({ address: user.account.address });
    const hash = await gwUser.write.bridge([SELECTOR, user.account.address, bridgeAmt, "0x"], {
      value: overpay,
    });
    const receipt = await pub.getTransactionReceipt({ hash });
    const gasCost = receipt.gasUsed * receipt.effectiveGasPrice;
    const after = await pub.getBalance({ address: user.account.address });

    // user should have paid only `exact` + gas (the 0.5 overpay refunded)
    const spent = before - after;
    expect(spent).to.equal(exact + gasCost, "only exact fee + gas spent; overpay refunded");
  });

  it("reverts when native sent is insufficient", async () => {
    const { mol, gw } = await setup();
    const bridgeAmt = 1000n * 10n ** 18n;
    const molUser = await viem.getContractAt("MolePin", mol.address, { client: { wallet: user } });
    await molUser.write.approve([gw.address, bridgeAmt]);
    const gwUser = await viem.getContractAt("MolePinBridgeGateway", gw.address, {
      client: { wallet: user },
    });
    // send far too little
    await viem.assertions.revert(
      gwUser.write.bridge([SELECTOR, user.account.address, bridgeAmt, "0x"], { value: 1n }),
    );
  });

  it("reverts on zero amount", async () => {
    const { gw } = await setup();
    const gwUser = await viem.getContractAt("MolePinBridgeGateway", gw.address, {
      client: { wallet: user },
    });
    await viem.assertions.revert(
      gwUser.write.bridge([SELECTOR, user.account.address, 0n, "0x"], { value: parseEther("1") }),
    );
  });
});