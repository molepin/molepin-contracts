// SPDX-License-Identifier: MIT
//
// Ignition module — BSC TESTNET home deployment.
// Deploys the MolePin home token and the bridge gateway using the verified BSC
// testnet CCIP router and BNB/USD feed. The CCT LockReleaseTokenPool + Token
// Admin Registry wiring is done afterwards by scripts/register-cct.ts (it needs
// post-deploy addresses and registry-specific calls).
//
// BSC 테스트넷 홈 배포 모듈. 검증된 BSC 테스트넷 CCIP 라우터와 BNB/USD 피드로
// MolePin 홈 토큰과 브릿지 게이트웨이를 배포한다. CCT LockReleaseTokenPool과
// Token Admin Registry 연결은 배포 후 scripts/register-cct.ts에서 수행한다.

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// BSC testnet CCIP router (verified). Confirm at https://docs.chain.link/ccip/directory
const BSC_TESTNET_CCIP_ROUTER = "0xE1053aE1857476f36A3C62580FF9b016E8EE8F6f";
// BSC testnet BNB/USD feed (verified).
const BSC_TESTNET_BNB_USD = "0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526";

export default buildModule("MolePinDeployHomeTestnet", (m) => {
  const initialOwner = m.getAccount(0);
  // Treasury defaults to deployer; override for production with a dedicated wallet.
  // treasury는 기본 배포자. 운영 시 전용 지갑으로 교체.
  const treasury = m.getAccount(0);

  const molePin = m.contract("MolePin", [initialOwner]);
  const gateway = m.contract("MolePinBridgeGateway", [
    initialOwner,
    molePin,
    BSC_TESTNET_CCIP_ROUTER,
    BSC_TESTNET_BNB_USD,
    treasury,
  ]);

  // NOTE: register destination chains after the remote gateways exist:
  //   gateway.setDestChain(<remote selector>, true)  // via scripts/register-cct.ts
  // 리모트 게이트웨이가 생긴 뒤 setDestChain으로 도착 체인 등록(스크립트에서).

  return { molePin, gateway };
});
