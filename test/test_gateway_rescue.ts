// ── Audit fixes #4 (trust revocation) & #5 (rescueERC20) ──────────────────────
//
// 감사 #4 수정: setTrustedRemoteGateway에 address(0) 허용 → 인바운드 신뢰 해지 가능.
//   (수정 전: require(gateway != address(0))로 한번 신뢰하면 인바운드 영구 개방.)
// 감사 #5 수정: rescueERC20 추가 → 게이트웨이에 갇힌 ERC20 회수 (sweepNative의 ERC20판).
//
// 아래 describe 블록을 MolePinBridgeGateway_test.ts 안(기존 describe와 같은 레벨)에 붙여넣으세요.
// 상수(SAMPLE_SELECTOR, BNB_PRICE_8DEC, CCIP_FEE)와 deployAll 패턴은 기존 파일과 동일합니다.

import { expect } from "chai";
import { network } from "hardhat";
import { parseEther } from "viem";

const SAMPLE_SELECTOR_2 = 13264668187771770619n;
const BNB_PRICE_8DEC_2 = 85_100_000_000n; // $851
const CCIP_FEE_2 = parseEther("0.0002");

describe("MolePinBridgeGateway — audit #4 & #5", () => {
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
    const feed = await viem.deployContract("MockPriceOracle", [8, BNB_PRICE_8DEC_2]);
    const router = await viem.deployContract("MockCCIPRouter", [CCIP_FEE_2]);
    const mol = await viem.deployContract("MolePin", [owner.account.address]);
    const gw = await viem.deployContract("MolePinBridgeGateway", [
      owner.account.address,
      treasury.account.address,
    ]);
    await gw.write.configure([mol.address, router.address, feed.address]);
    return { feed, router, mol, gw };
  }

  // ── #4: trusted remote gateway revocation ──────────────────────────────────
  it("can revoke inbound trust by setting the gateway to the zero address", async () => {
    const { gw } = await deployAll();

    // register trust first
    await gw.write.setTrustedRemoteGateway([SAMPLE_SELECTOR_2, gw.address]);
    expect((await gw.read.trustedRemoteGateway([SAMPLE_SELECTOR_2])).toLowerCase()).to.equal(
      gw.address.toLowerCase(),
    );

    // ✅ the fix: zero-address is now accepted as a revocation (no "zero addr" revert)
    await gw.write.setTrustedRemoteGateway([SAMPLE_SELECTOR_2, "0x0000000000000000000000000000000000000000"]);
    expect(await gw.read.trustedRemoteGateway([SAMPLE_SELECTOR_2])).to.equal(
      "0x0000000000000000000000000000000000000000",
    );
  });

  it("setTrustedRemoteGateway (incl. revocation) is owner-only", async () => {
    const { gw } = await deployAll();
    const gwAsUser = await viem.getContractAt("MolePinBridgeGateway", gw.address, {
      client: { wallet: user },
    });
    await viem.assertions.revertWithCustomError(
      gwAsUser.write.setTrustedRemoteGateway([SAMPLE_SELECTOR_2, gw.address]),
      gw,
      "OwnableUnauthorizedAccount",
    );
  });

  // ── #5: rescueERC20 ────────────────────────────────────────────────────────
  it("owner can rescue ERC20 tokens stranded in the gateway", async () => {
    const { gw, mol } = await deployAll();

    // simulate stranded tokens: send MOL straight to the gateway (mistake / failed CCIP return)
    const stranded = 1234n * 10n ** 18n;
    await mol.write.transfer([gw.address, stranded]);
    expect(await mol.read.balanceOf([gw.address])).to.equal(stranded);

    // rescue to the user
    const before = await mol.read.balanceOf([user.account.address]);
    await gw.write.rescueERC20([mol.address, user.account.address, stranded]);
    const after = await mol.read.balanceOf([user.account.address]);

    expect(after - before).to.equal(stranded, "rescued amount lands at the destination");
    expect(await mol.read.balanceOf([gw.address])).to.equal(0n, "gateway emptied");
  });

  it("rescueERC20 emits ERC20Rescued", async () => {
    const { gw, mol } = await deployAll();
    const stranded = 10n * 10n ** 18n;
    await mol.write.transfer([gw.address, stranded]);
    await viem.assertions.emit(
      gw.write.rescueERC20([mol.address, user.account.address, stranded]),
      gw,
      "ERC20Rescued",
    );
  });

  it("rescueERC20 is owner-only", async () => {
    const { gw, mol } = await deployAll();
    await mol.write.transfer([gw.address, 5n * 10n ** 18n]);
    const gwAsUser = await viem.getContractAt("MolePinBridgeGateway", gw.address, {
      client: { wallet: user },
    });
    await viem.assertions.revertWithCustomError(
      gwAsUser.write.rescueERC20([mol.address, user.account.address, 1n]),
      gw,
      "OwnableUnauthorizedAccount",
    );
  });

  it("rescueERC20 rejects zero addresses", async () => {
    const { gw, mol } = await deployAll();
    await viem.assertions.revert(
      gw.write.rescueERC20([mol.address, "0x0000000000000000000000000000000000000000", 1n]),
    );
  });
});
