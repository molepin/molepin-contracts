// ── Audit fix #3: DEFAULT_ADMIN_ROLE migrates atomically with 2-step ownership ──
//
// 감사 #3 수정 검증: Ownable2Step 소유권 이전 시 DEFAULT_ADMIN_ROLE도 함께 이관되는지.
// 수정 전: 소유권만 이전되고 admin role은 구 owner에 남아 권한-소유권 불일치 발생.
// 수정 후: acceptOwnership 시점에 구 owner revoke + 신 owner grant (원자적).
//
// 아래 describe 블록을 MolePinRemote_test.ts 파일 안(기존 describe와 같은 레벨)에 붙여넣으세요.
// import / before 훅은 기존 파일 것을 재사용하므로 중복 선언하지 마세요.

import { expect } from "chai";
import { network } from "hardhat";

const ADMIN_ROLE = "0x0000000000000000000000000000000000000000000000000000000000000000"; // DEFAULT_ADMIN_ROLE = bytes32(0)

describe("MolePinRemote — audit #3: admin role syncs on ownership transfer", () => {
  let viem: any;
  let owner: any; // initial deployer (A)
  let newOwner: any; // incoming owner, e.g. the multisig (B)
  let pool: any;

  before(async () => {
    const conn = await network.getOrCreate();
    viem = conn.viem;
    [owner, newOwner, pool] = await viem.getWalletClients();
  });

  async function deploy() {
    return viem.deployContract("MolePinRemote", [owner.account.address]);
  }

  // helper: rebind a contract to a specific signer
  async function asSigner(remote: any, wallet: any) {
    return viem.getContractAt("MolePinRemote", remote.address, { client: { wallet } });
  }

  it("at deploy, the initial owner holds both ownership and DEFAULT_ADMIN_ROLE", async () => {
    const remote = await deploy();
    expect((await remote.read.owner()).toLowerCase()).to.equal(owner.account.address.toLowerCase());
    expect(await remote.read.hasRole([ADMIN_ROLE, owner.account.address])).to.equal(true);
  });

  it("after a completed 2-step transfer, the NEW owner holds DEFAULT_ADMIN_ROLE", async () => {
    const remote = await deploy();

    // step 1: current owner nominates the new owner (B becomes pending)
    await remote.write.transferOwnership([newOwner.account.address]);
    expect((await remote.read.pendingOwner()).toLowerCase()).to.equal(
      newOwner.account.address.toLowerCase(),
    );
    // ownership not transferred yet — A is still owner & admin
    expect((await remote.read.owner()).toLowerCase()).to.equal(owner.account.address.toLowerCase());

    // step 2: new owner accepts → _transferOwnership override runs
    const remoteAsNew = await asSigner(remote, newOwner);
    await remoteAsNew.write.acceptOwnership();

    // ownership moved to B
    expect((await remote.read.owner()).toLowerCase()).to.equal(
      newOwner.account.address.toLowerCase(),
    );
    // ✅ the core fix: admin role moved to B …
    expect(await remote.read.hasRole([ADMIN_ROLE, newOwner.account.address])).to.equal(true);
    // … and was revoked from A
    expect(await remote.read.hasRole([ADMIN_ROLE, owner.account.address])).to.equal(false);
  });

  it("the NEW owner can call grantPoolRoles after accepting ownership", async () => {
    const remote = await deploy();
    await remote.write.transferOwnership([newOwner.account.address]);
    const remoteAsNew = await asSigner(remote, newOwner);
    await remoteAsNew.write.acceptOwnership();

    // B (new owner/admin) grants pool roles — must succeed
    await remoteAsNew.write.grantPoolRoles([pool.account.address]);
    const MINTER = await remote.read.MINTER_ROLE();
    const BURNER = await remote.read.BURNER_ROLE();
    expect(await remote.read.hasRole([MINTER, pool.account.address])).to.equal(true);
    expect(await remote.read.hasRole([BURNER, pool.account.address])).to.equal(true);
  });

  it("the OLD owner can NO LONGER call grantPoolRoles after the transfer", async () => {
    const remote = await deploy();
    await remote.write.transferOwnership([newOwner.account.address]);
    const remoteAsNew = await asSigner(remote, newOwner);
    await remoteAsNew.write.acceptOwnership();

    // A lost the admin role → grantPoolRoles must revert
    const remoteAsOld = await asSigner(remote, owner);
    await viem.assertions.revertWithCustomError(
      remoteAsOld.write.grantPoolRoles([pool.account.address]),
      remote,
      "AccessControlUnauthorizedAccount",
    );
  });

  it("grantMintAndBurnRoles is also admin-only (audit #7, explicit modifier)", async () => {
    const remote = await deploy();
    const remoteAsPool = await asSigner(remote, pool); // pool has no admin role
    await viem.assertions.revertWithCustomError(
      remoteAsPool.write.grantMintAndBurnRoles([pool.account.address]),
      remote,
      "AccessControlUnauthorizedAccount",
    );
  });
});
