const { expect } = require("chai");
const { ethers } = require("hardhat");

// helper: address → bytes32 (left-padded), matches gateway buildSendParam
const toBytes32 = (addr) => ethers.zeroPadValue(addr, 32);

describe("MolePinBridgeGatewayLZ", function () {
  const FEE_MODE_USD_FIXED = 0;
  const FEE_MODE_LZ_MULTIPLE = 1;
  const DST_EID = 30102; // arbitrary remote eid
  const LZ_FEE = ethers.parseEther("0.01"); // mock lzFee
  const ORACLE_DECIMALS = 8;
  const BNB_USD = 600n * 10n ** 8n; // $600/BNB at 8 decimals
  const EXTRA_OPTS = "0x0003"; // dummy options bytes

  let owner, treasury, user, other;
  let mol, oracle, oft, gateway;

  beforeEach(async function () {
    [owner, treasury, user, other] = await ethers.getSigners();

    mol = await (await ethers.getContractFactory("MockMOL")).deploy();
    oracle = await (await ethers.getContractFactory("MockPriceOracle")).deploy(ORACLE_DECIMALS, BNB_USD);
    oft = await (await ethers.getContractFactory("MockOFT")).deploy(await mol.getAddress(), LZ_FEE);
    gateway = await (await ethers.getContractFactory("MolePinBridgeGatewayLZ"))
      .deploy(owner.address, treasury.address);

    // fund user with MOL and approve gateway
    await mol.mint(user.address, ethers.parseEther("1000000"));
    await mol.connect(user).approve(await gateway.getAddress(), ethers.MaxUint256);
  });

  // ── Constructor & configure ─────────────────────────────────────────────
  describe("constructor & configure", function () {
    it("sets owner and treasury", async function () {
      expect(await gateway.owner()).to.equal(owner.address);
      expect(await gateway.treasury()).to.equal(treasury.address);
    });

    it("reverts constructor with zero treasury", async function () {
      const F = await ethers.getContractFactory("MolePinBridgeGatewayLZ");
      await expect(F.deploy(owner.address, ethers.ZeroAddress)).to.be.revertedWith("zero addr");
    });

    it("configure (USD_FIXED) caches token, oracle, decimals, mode", async function () {
      await gateway.configure(await oft.getAddress(), await oracle.getAddress(), FEE_MODE_USD_FIXED);
      expect(await gateway.configured()).to.equal(true);
      expect(await gateway.feeMode()).to.equal(FEE_MODE_USD_FIXED);
      expect(await gateway.MOL()).to.equal(await mol.getAddress());
      expect(await gateway.OFT()).to.equal(await oft.getAddress());
      expect(await gateway.NATIVE_FEED_DECIMALS()).to.equal(ORACLE_DECIMALS);
    });

    it("configure (LZ_MULTIPLE) needs no oracle", async function () {
      await gateway.configure(await oft.getAddress(), ethers.ZeroAddress, FEE_MODE_LZ_MULTIPLE);
      expect(await gateway.feeMode()).to.equal(FEE_MODE_LZ_MULTIPLE);
      expect(await gateway.NATIVE_USD()).to.equal(ethers.ZeroAddress);
    });

    it("configure (USD_FIXED) reverts without oracle", async function () {
      await expect(
        gateway.configure(await oft.getAddress(), ethers.ZeroAddress, FEE_MODE_USD_FIXED)
      ).to.be.revertedWith("feed required");
    });

    it("configure twice reverts", async function () {
      await gateway.configure(await oft.getAddress(), await oracle.getAddress(), FEE_MODE_USD_FIXED);
      await expect(
        gateway.configure(await oft.getAddress(), await oracle.getAddress(), FEE_MODE_USD_FIXED)
      ).to.be.revertedWith("configured");
    });

    it("configure rejects bad mode", async function () {
      await expect(
        gateway.configure(await oft.getAddress(), await oracle.getAddress(), 2)
      ).to.be.revertedWith("bad mode");
    });

    it("configure only by owner", async function () {
      await expect(
        gateway.connect(user).configure(await oft.getAddress(), await oracle.getAddress(), FEE_MODE_USD_FIXED)
      ).to.be.revertedWithCustomError(gateway, "OwnableUnauthorizedAccount");
    });
  });

  // ── Fee math: USD_FIXED (BSC home) ──────────────────────────────────────
  describe("fee math — USD_FIXED ($1 @ $600/BNB)", function () {
    beforeEach(async function () {
      await gateway.configure(await oft.getAddress(), await oracle.getAddress(), FEE_MODE_USD_FIXED);
      await gateway.setDstEid(DST_EID, true);
    });

    it("molepinFeeUsdFixed = $1 / $600 = 1/600 BNB", async function () {
      // feeUsd(1e18) * 10^8 / 600e8 = 1e18/600
      const expected = (ethers.parseEther("1") * (10n ** BigInt(ORACLE_DECIMALS))) / BNB_USD;
      expect(await gateway.molepinFeeUsdFixed()).to.equal(expected);
    });

    it("quote returns lzFee + $1-in-BNB", async function () {
      const [lzFee, molepinFee, total] = await gateway.quote(
        DST_EID, user.address, ethers.parseEther("100"), 0, EXTRA_OPTS
      );
      expect(lzFee).to.equal(LZ_FEE);
      expect(molepinFee).to.equal(ethers.parseEther("1") * 10n ** 8n / BNB_USD);
      expect(total).to.equal(lzFee + molepinFee);
    });

    it("reverts molepinFeeLzMultiple in wrong mode", async function () {
      await expect(gateway.molepinFeeLzMultiple(LZ_FEE)).to.be.revertedWith("wrong mode");
    });

    it("reverts on stale oracle", async function () {
      await oracle.setUpdatedAt(1); // ancient
      await expect(gateway.molepinFeeUsdFixed()).to.be.revertedWith("stale oracle");
    });

    it("reverts on non-positive price", async function () {
      await oracle.setPrice(0);
      await expect(gateway.molepinFeeUsdFixed()).to.be.revertedWith("bad oracle price");
    });

    it("respects $5 cap on setFeeUsd", async function () {
      await expect(gateway.setFeeUsd(ethers.parseEther("6"))).to.be.revertedWith("exceeds max $5");
      await gateway.setFeeUsd(ethers.parseEther("5"));
      expect(await gateway.feeUsd()).to.equal(ethers.parseEther("5"));
    });
  });

  // ── Fee math: LZ_MULTIPLE (remote) ──────────────────────────────────────
  describe("fee math — LZ_MULTIPLE (2x default)", function () {
    beforeEach(async function () {
      await gateway.configure(await oft.getAddress(), ethers.ZeroAddress, FEE_MODE_LZ_MULTIPLE);
      await gateway.setDstEid(DST_EID, true);
    });

    it("default multiplier 20000 bps = 2x lzFee", async function () {
      expect(await gateway.feeMultiplierBps()).to.equal(20000);
      expect(await gateway.molepinFeeLzMultiple(LZ_FEE)).to.equal(LZ_FEE * 2n);
    });

    it("quote total = lzFee + 2*lzFee = 3*lzFee", async function () {
      const [lzFee, molepinFee, total] = await gateway.quote(
        DST_EID, user.address, ethers.parseEther("100"), 0, EXTRA_OPTS
      );
      expect(molepinFee).to.equal(LZ_FEE * 2n);
      expect(total).to.equal(LZ_FEE * 3n);
    });

    it("setFeeMultiplierBps respects 5x cap", async function () {
      await expect(gateway.setFeeMultiplierBps(50001)).to.be.revertedWith("exceeds 5x");
      await gateway.setFeeMultiplierBps(30000);
      expect(await gateway.molepinFeeLzMultiple(LZ_FEE)).to.equal(LZ_FEE * 3n);
    });

    it("reverts molepinFeeUsdFixed in wrong mode", async function () {
      await expect(gateway.molepinFeeUsdFixed()).to.be.revertedWith("wrong mode");
    });
  });

  // ── bridge() single-transaction flow ────────────────────────────────────
  describe("bridge() — atomic single-tx (USD_FIXED)", function () {
    const AMOUNT = ethers.parseEther("100");
    let molepinFee, total;

    beforeEach(async function () {
      await gateway.configure(await oft.getAddress(), await oracle.getAddress(), FEE_MODE_USD_FIXED);
      await gateway.setDstEid(DST_EID, true);
      molepinFee = ethers.parseEther("1") * 10n ** 8n / BNB_USD;
      total = LZ_FEE + molepinFee;
    });

    it("collects native fee to treasury, forwards lzFee to OFT, pulls MOL", async function () {
      const treBefore = await ethers.provider.getBalance(treasury.address);

      await expect(
        gateway.connect(user).bridge(DST_EID, user.address, AMOUNT, 0, EXTRA_OPTS, { value: total })
      ).to.emit(gateway, "BridgeInitiated");

      // treasury got exactly molepinFee
      const treAfter = await ethers.provider.getBalance(treasury.address);
      expect(treAfter - treBefore).to.equal(molepinFee);

      // OFT received exactly lzFee as msg.value, and the MOL tokens
      expect(await oft.lastValueReceived()).to.equal(LZ_FEE);
      expect(await oft.lastAmountLD()).to.equal(AMOUNT);
      expect(await mol.balanceOf(await oft.getAddress())).to.equal(AMOUNT);
      // recipient encoded as bytes32 of the user
      expect(await oft.lastTo()).to.equal(toBytes32(user.address));
    });

    it("refunds overpayment to caller", async function () {
      const over = ethers.parseEther("0.5");
      const balBefore = await ethers.provider.getBalance(user.address);

      const tx = await gateway.connect(user).bridge(
        DST_EID, user.address, AMOUNT, 0, EXTRA_OPTS, { value: total + over }
      );
      const rc = await tx.wait();
      const gasCost = rc.gasUsed * rc.gasPrice;

      const balAfter = await ethers.provider.getBalance(user.address);
      // user paid only `total` + gas; the `over` was refunded
      expect(balBefore - balAfter).to.equal(total + gasCost);
    });

    it("reverts on insufficient native", async function () {
      await expect(
        gateway.connect(user).bridge(DST_EID, user.address, AMOUNT, 0, EXTRA_OPTS, { value: total - 1n })
      ).to.be.revertedWith("insufficient native");
    });

    it("reverts on zero amount / zero recipient / disallowed dst", async function () {
      await expect(
        gateway.connect(user).bridge(DST_EID, user.address, 0, 0, EXTRA_OPTS, { value: total })
      ).to.be.revertedWith("zero amount");
      await expect(
        gateway.connect(user).bridge(DST_EID, ethers.ZeroAddress, AMOUNT, 0, EXTRA_OPTS, { value: total })
      ).to.be.revertedWith("zero recipient");
      await expect(
        gateway.connect(user).bridge(99999, user.address, AMOUNT, 0, EXTRA_OPTS, { value: total })
      ).to.be.revertedWith("dst not allowed");
    });

    it("reverts when fee transfer to treasury fails", async function () {
      const rejecting = await (await ethers.getContractFactory("RejectingTreasury")).deploy();
      await gateway.setTreasury(await rejecting.getAddress());
      await expect(
        gateway.connect(user).bridge(DST_EID, user.address, AMOUNT, 0, EXTRA_OPTS, { value: total })
      ).to.be.revertedWith("fee transfer failed");
    });

    it("no MOL is left resting in the gateway after bridge", async function () {
      await gateway.connect(user).bridge(DST_EID, user.address, AMOUNT, 0, EXTRA_OPTS, { value: total });
      expect(await mol.balanceOf(await gateway.getAddress())).to.equal(0);
    });

    it("reverts bridge before configure", async function () {
      const fresh = await (await ethers.getContractFactory("MolePinBridgeGatewayLZ"))
        .deploy(owner.address, treasury.address);
      await expect(
        fresh.connect(user).bridge(DST_EID, user.address, AMOUNT, 0, EXTRA_OPTS, { value: total })
      ).to.be.revertedWith("not configured");
    });
  });

  // ── bridge() in LZ_MULTIPLE mode ────────────────────────────────────────
  describe("bridge() — LZ_MULTIPLE", function () {
    const AMOUNT = ethers.parseEther("50");

    beforeEach(async function () {
      await gateway.configure(await oft.getAddress(), ethers.ZeroAddress, FEE_MODE_LZ_MULTIPLE);
      await gateway.setDstEid(DST_EID, true);
    });

    it("treasury gets 2x lzFee, OFT gets lzFee", async function () {
      const molepinFee = LZ_FEE * 2n;
      const total = LZ_FEE + molepinFee;
      const treBefore = await ethers.provider.getBalance(treasury.address);

      await gateway.connect(user).bridge(DST_EID, user.address, AMOUNT, 0, EXTRA_OPTS, { value: total });

      const treAfter = await ethers.provider.getBalance(treasury.address);
      expect(treAfter - treBefore).to.equal(molepinFee);
      expect(await oft.lastValueReceived()).to.equal(LZ_FEE);
    });
  });

  // ── Owner controls ──────────────────────────────────────────────────────
  describe("owner controls", function () {
    beforeEach(async function () {
      await gateway.configure(await oft.getAddress(), await oracle.getAddress(), FEE_MODE_USD_FIXED);
    });

    it("setTreasury / setDstEid / setFeeUsd onlyOwner", async function () {
      await expect(gateway.connect(user).setTreasury(other.address))
        .to.be.revertedWithCustomError(gateway, "OwnableUnauthorizedAccount");
      await expect(gateway.connect(user).setDstEid(DST_EID, true))
        .to.be.revertedWithCustomError(gateway, "OwnableUnauthorizedAccount");
      await expect(gateway.connect(user).setFeeUsd(ethers.parseEther("2")))
        .to.be.revertedWithCustomError(gateway, "OwnableUnauthorizedAccount");
    });

    it("setTreasury rejects zero", async function () {
      await expect(gateway.setTreasury(ethers.ZeroAddress)).to.be.revertedWith("zero addr");
    });

    it("sweepNative recovers stuck native", async function () {
      // force some native into the gateway
      await owner.sendTransaction({ to: await gateway.getAddress(), value: ethers.parseEther("1") });
      const balBefore = await ethers.provider.getBalance(other.address);
      await gateway.sweepNative(other.address);
      const balAfter = await ethers.provider.getBalance(other.address);
      expect(balAfter - balBefore).to.equal(ethers.parseEther("1"));
    });

    it("sweepToken recovers stuck ERC20", async function () {
      await mol.mint(await gateway.getAddress(), ethers.parseEther("5"));
      await gateway.sweepToken(await mol.getAddress(), other.address, ethers.parseEther("5"));
      expect(await mol.balanceOf(other.address)).to.equal(ethers.parseEther("5"));
    });
  });
});
