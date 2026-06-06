// SPDX-License-Identifier: MIT
//
// Ignition module — local deployment with Mock dependencies.
// Deploys the MolePin home token, mock price feed + mock CCIP router, and the
// bridge gateway, so the full fee-charging flow can be exercised locally.
//
// 로컬 배포 모듈. MolePin 홈 토큰, mock 가격 피드 + mock CCIP 라우터, 브릿지
// 게이트웨이를 배포하여 수수료 징수 흐름 전체를 로컬에서 시험할 수 있다.

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MOCK_BNB_USD = 85_100_000_000n; // $851 with 8 decimals
const MOCK_CCIP_FEE = 2_000_000_000_000_000n; // 0.002 native (~test value)

export default buildModule("MolePinDeployLocal", (m) => {
  const initialOwner = m.getAccount(0);
  const treasury = m.getAccount(1); // distinct from owner so fee transfers are visible

  // ── Mocks ─────────────────────────────────────────────────────────────────
  const mockFeed = m.contract("MockPriceOracle", [8, MOCK_BNB_USD], { id: "MockBnbUsd" });
  const mockRouter = m.contract("MockCCIPRouter", [MOCK_CCIP_FEE], { id: "MockRouter" });

  // ── Core ──────────────────────────────────────────────────────────────────
  const molePin = m.contract("MolePin", [initialOwner]);
  const gateway = m.contract("MolePinBridgeGateway", [
    initialOwner,
    molePin,
    mockRouter,
    mockFeed,
    treasury,
  ]);

  // ── Wiring ────────────────────────────────────────────────────────────────
  // Allow a sample destination selector so bridge() passes the allowlist check.
  // bridge()의 화이트리스트 검사를 통과하도록 샘플 도착 selector를 허용.
  m.call(gateway, "setDestChain", [13264668187771770619n, true], { id: "AllowSampleDest" });

  return { molePin, gateway, mockFeed, mockRouter };
});
