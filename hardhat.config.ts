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
const ETHEREUM_RPC_URL = process.env.ETHEREUM_RPC_URL ?? "https://eth.llamarpc.com";
const AVALANCHE_RPC_URL = process.env.AVALANCHE_RPC_URL ?? "https://api.avax.network/ext/bc/C/rpc";
const BASE_SEPOLIA_RPC_URL = process.env.BASE_SEPOLIA_RPC_URL ?? "https://sepolia.base.org";
const ARBITRUM_SEPOLIA_RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL ?? "https://sepolia-rollup.arbitrum.io/rpc";

const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;

// Block-explorer API key (verify). BscScan is the primary (home chain).
// Other chains' keys live in .env; swap into BSCSCAN_API_KEY's slot when
// verifying on those chains, or use an Etherscan V2 multichain key.
const BSCSCAN_API_KEY = process.env.BSCSCAN_API_KEY ?? "";

function liveAccounts(): string[] {
  const keys: string[] = [];

  // 64-hex(32바이트) 개인키만 통과. 주소(40 hex)·빈 값·잘못된 형식은 버림.
  // 이게 없으면 OWNER_PRIVATE_KEY에 주소가 들어갔을 때 11개 네트워크가 전부 죽음.
  const norm = (v?: string): string | null => {
    if (!v) return null;
    const k = v.startsWith("0x") ? v : `0x${v}`;
    return /^0x[0-9a-fA-F]{64}$/.test(k) ? k : null;
  };

  // owner 먼저 (게이트웨이 배포 + 권한 작업, 7체인 가스 보유)
  const ownerKey = norm(process.env.OWNER_PRIVATE_KEY);
  if (ownerKey) keys.push(ownerKey);

  // 배포 지갑 두 번째 (필요 시)
  const deployerKey = norm(DEPLOYER_PRIVATE_KEY);
  if (deployerKey) keys.push(deployerKey);

  return keys;
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
    baseSepolia: {
      type: "http",
      chainType: "op",
      url: BASE_SEPOLIA_RPC_URL,
      accounts: liveAccounts(),
      chainId: 84532,
    },
    arbitrumSepolia: {
      type: "http",
      chainType: "l1",
      url: ARBITRUM_SEPOLIA_RPC_URL,
      accounts: liveAccounts(),
      chainId: 421614,
    },
    optimism: {
      type: "http",
      chainType: "op",
      url: OPTIMISM_RPC_URL,
      accounts: liveAccounts(),
      chainId: 10,
    },
    // hardhat.config.ts networks 안에 추가
    ethereum: {
      type: "http",
      chainType: "l1",
      url: ETHEREUM_RPC_URL,
      accounts: liveAccounts(),
      chainId: 1,
    },
    avalanche: {
      type: "http",
      chainType: "l1",
      url: AVALANCHE_RPC_URL,
      accounts: liveAccounts(),
      chainId: 43114,
      gasPrice: 30000000000,
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
        salt: process.env.DEPLOY_SALT ?? "0x0000000000000000000000000000000000000000000000000000000000000000",
      },
    },
  },
};

export default config;