const { expect } = require("chai");
const { ethers } = require("hardhat");
const { Options } = require("@layerzerolabs/lz-v2-utilities");
const { buildLzReceiveOption, defaultBridgeOptions, MOLEPIN_DEFAULT_LZRECEIVE_GAS } = require("../scripts/lz-options.js");

// Cross-check the THREE producers of LayerZero extraOptions agree byte-for-byte:
//   1. LayerZero official @layerzerolabs/lz-v2-utilities Options (the source of truth)
//   2. our off-chain JS builder (scripts/lz-options.js)
//   3. our on-chain Solidity lib (MolePinLzOptions via LzOptionsHarness)
// If any pair diverges, the gateway could send malformed options → stuck messages.

describe("LZ extraOptions builder — 3-way byte parity", function () {
  let harness;

  const official = (gas, value) =>
    Options.newOptions().addExecutorLzReceiveOption(gas, value).toHex().toLowerCase();

  before(async function () {
    harness = await (await ethers.getContractFactory("LzOptionsHarness")).deploy();
  });

  const cases = [
    ["50k, no value", 50000n, 0n],
    ["200k, no value", 200000n, 0n],
    ["1M, no value", 1000000n, 0n],
    ["200k + 1e18 value", 200000n, ethers.parseEther("1")],
    ["250k + 0.5 ETH value", 250000n, ethers.parseEther("0.5")],
    ["max-ish gas, no value", (2n ** 64n), 0n],
  ];

  for (const [name, gas, value] of cases) {
    it(`matches across JS / Solidity / official — ${name}`, async function () {
      const off = official(gas, value);
      const js = buildLzReceiveOption(gas, value).toLowerCase();

      // Solidity: use no-value overload when value==0 to also exercise that path
      const sol = (value === 0n
        ? await harness.lzReceiveNoValue(gas)
        : await harness.lzReceive(gas, value)
      ).toLowerCase();

      expect(js).to.equal(off, "JS != official");
      expect(sol).to.equal(off, "Solidity != official");
      expect(sol).to.equal(js, "Solidity != JS");
    });
  }

  it("Solidity lzReceive(gas) and lzReceive(gas,0) are identical", async function () {
    const a = await harness.lzReceiveNoValue(200000n);
    const b = await harness.lzReceive(200000n, 0n);
    expect(a).to.equal(b);
  });

  it("default bridge options = 200k gas, no value, matches official", async function () {
    expect(MOLEPIN_DEFAULT_LZRECEIVE_GAS).to.equal(200000n);
    expect(defaultBridgeOptions().toLowerCase())
      .to.equal(official(200000n, 0n));
  });

  it("rejects out-of-range gas in JS builder", function () {
    expect(() => buildLzReceiveOption(2n ** 128n, 0n)).to.throw("gas out of uint128 range");
  });
});
