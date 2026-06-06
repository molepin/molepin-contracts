// SPDX-License-Identifier: MIT
//
// Tests for MolePinRemote: starts at 0 supply, only the pool (granted roles)
// can mint/burn, unauthorized mint reverts, and grantPoolRoles wiring works.
// This is the immutability guarantee on remote chains — no free minting.
//
// MolePinRemote 테스트: 0 공급에서 시작, 풀(권한 부여됨)만 mint/burn 가능,
// 무권한 mint는 revert, grantPoolRoles 동작. 리모트 체인의 불변성 보장.

import { expect } from "chai";
import { network } from "hardhat";

describe("MolePinRemote (remote token)", () => {
  let viem: any;
  let owner: any;
  let pool: any; // stands in for the CCT BurnMintTokenPool
  let user: any;

  before(async () => {
    const conn = await network.getOrCreate();
    viem = conn.viem;
    [owner, pool, user] = await viem.getWalletClients();
  });

  async function deploy() {
    return viem.deployContract("MolePinRemote", [owner.account.address]);
  }

  it("starts at zero supply (nothing minted at deploy)", async () => {
    const remote = await deploy();
    expect(await remote.read.totalSupply()).to.equal(0n);
  });

  it("has correct name/symbol/decimals", async () => {
    const remote = await deploy();
    expect(await remote.read.name()).to.equal("MolePin");
    expect(await remote.read.symbol()).to.equal("MOL");
    expect(await remote.read.decimals()).to.equal(18);
  });

  it("rejects mint from a non-pool address (AccessControlUnauthorizedAccount)", async () => {
    const remote = await deploy();
    const remoteAsPool = await viem.getContractAt("MolePinRemote", remote.address, {
      client: { wallet: pool },
    });
    await viem.assertions.revertWithCustomError(
      remoteAsPool.write.mint([user.account.address, 1000n * 10n ** 18n]),
      remote,
      "AccessControlUnauthorizedAccount",
    );
  });

  it("grants pool roles and then allows mint", async () => {
    const remote = await deploy();
    await remote.write.grantPoolRoles([pool.account.address]);

    const remoteAsPool = await viem.getContractAt("MolePinRemote", remote.address, {
      client: { wallet: pool },
    });
    const amount = 5000n * 10n ** 18n;
    await remoteAsPool.write.mint([user.account.address, amount]);

    expect(await remote.read.balanceOf([user.account.address])).to.equal(amount);
    expect(await remote.read.totalSupply()).to.equal(amount);
  });

  it("pool can burn (reduces supply 1:1 with bridge-back)", async () => {
    const remote = await deploy();
    await remote.write.grantPoolRoles([pool.account.address]);
    const remoteAsPool = await viem.getContractAt("MolePinRemote", remote.address, {
      client: { wallet: pool },
    });
    const amount = 5000n * 10n ** 18n;
    await remoteAsPool.write.mint([pool.account.address, amount]);
    await remoteAsPool.write.burn([amount]);
    expect(await remote.read.totalSupply()).to.equal(0n, "burn returns supply to 0");
  });

  it("grantPoolRoles is admin-only (AccessControlUnauthorizedAccount)", async () => {
    const remote = await deploy();
    const remoteAsUser = await viem.getContractAt("MolePinRemote", remote.address, {
      client: { wallet: user },
    });
    await viem.assertions.revertWithCustomError(
      remoteAsUser.write.grantPoolRoles([user.account.address]),
      remote,
      "AccessControlUnauthorizedAccount",
    );
  });
});