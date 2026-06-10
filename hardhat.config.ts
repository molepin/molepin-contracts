// SPDX-License-Identifier: MIT
//
// Hardhat 3 configuration for the MolePin smart contracts.
// MolePin: BSC-native MemeFi token with Chainlink CCT multichain bridging.
// (KO: BSC를 홈 체인으로 하는 MemeFi 토큰 + Chainlink CCT 멀티체인.)

import type { HardhatUserConfig } from "hardhat/config";
import HardhatToolboxViem from "@nomicfoundation/hardhat-toolbox-viem";
import HardhatIgnition from "@nomicfoundation/hardhat-ignition";
import HardhatMocha from "@nomicfoundation/hardhat-mocha";
import HardhatVerify from "@nomicfoundation/hardhat-verify";
import "dotenv/config";

// ── Environment / 환경 변수 ────────────────────────────────────────────────
// Home chain = BSC. Remote chains = Polygon / Base / Arbitrum / Optimism / ...
const BSC_RPC_URL = process.env.BSC_RPC_URL ?? "https://bsc-dataseed.binance.org";
const BSC_TESTNET_RPC_URL =
  process.env.BSC_TESTNET_RPC_URL ?? "https://data-seed-prebsc-1-s1.binance.org:8545";
const POLYGON_RPC_URL = process.env.POLYGON_RPC_URL ?? "https://polygon-rpc.com";
const AMOY_RPC_URL = process.env.AMOY_RPC_URL ?? "https://rpc-amoy.polygon.technology";
const BASE_RPC_URL = process.env.BASE_RPC_URL ?? "https://mainnet.base.org";
const ARBITRUM_RPC_URL = process.env.ARBITRUM_RPC_URL ?? "https://arb1.arbitrum.io/rpc";
const OPTIMISM_RPC_URL = process.env.OPTIMISM_RPC_URL ?? "https://mainnet.optimism.io";

const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;

// Block-explorer API key (verify). BscScan is the primary (home chain).
// Other chains' keys live in .env; swap into BSCSCAN_API_KEY's slot when
// verifying on those chains, or use an Etherscan V2 multichain key.
const BSCSCAN_API_KEY = process.env.BSCSCAN_API_KEY ?? "";

function liveAccounts(): string[] {
  if (!DEPLOYER_PRIVATE_KEY) return [];
  return [DEPLOYER_PRIVATE_KEY.startsWith("0x") ? DEPLOYER_PRIVATE_KEY : `0x${DEPLOYER_PRIVATE_KEY}`];
}

const config: HardhatUserConfig = {
  plugins: [HardhatToolboxViem, HardhatIgnition, HardhatMocha, HardhatVerify],

  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: { enabled: true, runs: 200 },
          viaIR: true,
          evmVersion: "cancun",
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: { enabled: true, runs: 200 },
          viaIR: true,
          evmVersion: "cancun",
        },
      },
    },
  },

  paths: {
    tests: {
      mocha: "test",
    },
  },

  test: {
    mocha: {
      timeout: 60000,
    },
  },

  networks: {
    hardhat: {
      type: "edr-simulated",
      chainType: "l1",
    },
    // ── Home chain (BSC) ──────────────────────────────────────────────────
    bsc: {
      type: "http",
      chainType: "l1",
      url: BSC_RPC_URL,
      accounts: liveAccounts(),
      chainId: 56,
    },
    bscTestnet: {
      type: "http",
      chainType: "l1",
      url: BSC_TESTNET_RPC_URL,
      accounts: liveAccounts(),
      chainId: 97,
    },
    // ── Remote chains (EVM) ───────────────────────────────────────────────
    polygon: {
      type: "http",
      chainType: "l1",
      url: POLYGON_RPC_URL,
      accounts: liveAccounts(),
      chainId: 137,
    },
    amoy: {
      type: "http",
      chainType: "l1",
      url: AMOY_RPC_URL,
      accounts: liveAccounts(),
      chainId: 80002,
    },
    base: {
      type: "http",
      chainType: "op",
      url: BASE_RPC_URL,
      accounts: liveAccounts(),
      chainId: 8453,
    },
    arbitrum: {
      type: "http",
      chainType: "l1",
      url: ARBITRUM_RPC_URL,
      accounts: liveAccounts(),
      chainId: 42161,
    },
    optimism: {
      type: "http",
      chainType: "op",
      url: OPTIMISM_RPC_URL,
      accounts: liveAccounts(),
      chainId: 10,
    },
  },

  // Etherscan-family verify. Hardhat 3 expects a single API key string here.
  // Home chain is BSC -> default to BscScan key. To verify on another chain,
  // set BSCSCAN_API_KEY in .env to that chain's explorer key for that run, or
  // pass the key inline. (Etherscan V2 keys often work across chains.)
  // (KO: Hardhat 3는 단일 키 문자열만 받음. 홈은 BSC라 BscScan 키 기본.
  //  다른 체인 verify 시 그 체인 키로 교체해 실행.)
  verify: {
    etherscan: {
      apiKey: BSCSCAN_API_KEY,
    },
  },
  ignition: {
    strategyConfig: {
      create2: {
        salt: "0xc5147ddf842719cbbf729ea3fe293d2495872a508273e34e78c2a83c617d187b",
      },
    },
  },
};

export default config;