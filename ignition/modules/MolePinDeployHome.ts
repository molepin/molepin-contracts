// SPDX-License-Identifier: MIT
//
// Ignition module — BSC MAINNET home deployment.
// Production home-chain deploy: MolePin token + bridge gateway with the BSC
// mainnet CCIP router and BNB/USD feed. The CCT LockReleaseTokenPool + Token
// Admin Registry wiring follows via scripts/register-cct.ts.
//
// BSC 메인넷 홈 배포 모듈. 운영용 홈 체인 배포: MolePin 토큰 + 브릿지 게이트웨이
// (BSC 메인넷 CCIP 라우터, BNB/USD 피드). CCT 풀과 레지스트리 연결은
// scripts/register-cct.ts에서 수행한다.

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// BSC mainnet BNB/USD feed (verified).
const BSC_BNB_USD = "0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE";
// BSC mainnet CCIP router — CONFIRM before deploy:
// https://docs.chain.link/ccip/directory/mainnet/chain/bsc-mainnet
const BSC_CCIP_ROUTER = "0x34B03Cb9086d7D758AC55af71584F81A598759FE";

export default buildModule("MolePinDeployHome", (m) => {
  const initialOwner = m.getAccount(0);
  // For production, pass a dedicated treasury wallet and later move ownership
  // to a multisig / timelock.
  // 운영 시 전용 treasury 지갑을 쓰고, 소유권은 멀티시그/타임락으로 이전 권장.
  const treasury = m.getParameter("treasury", m.getAccount(0));

  const molePin = m.contract("MolePin", [initialOwner]);
  const gateway = m.contract("MolePinBridgeGateway", [
    initialOwner,
    molePin,
    BSC_CCIP_ROUTER,
    BSC_BNB_USD,
    treasury,
  ]);

  return { molePin, gateway };
});
