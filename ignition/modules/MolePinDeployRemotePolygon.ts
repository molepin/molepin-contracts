// SPDX-License-Identifier: MIT
//
// Ignition module — Polygon (remote) deployment.
// Deploys MolePinRemote (pool-only mint/burn) and the bridge gateway for
// Polygon, using the Polygon CCIP router and the POL/USD feed (Polygon gas is
// POL, NOT ETH). The CCT BurnMintTokenPool + grantPoolRoles + Token Admin
// Registry wiring follow via scripts/register-cct.ts.
//
// Polygon(리모트) 배포 모듈. MolePinRemote와 Polygon용 브릿지 게이트웨이를
// 배포하며, Polygon CCIP 라우터와 POL/USD 피드를 사용한다(Polygon 가스는
// ETH가 아니라 POL). 풀·권한·레지스트리 연결은 scripts/register-cct.ts에서.
//
// ⚠ Polygon gas token is POL -> use POL/USD. Using ETH/USD = ~thousand-fold error.
// ⚠ Polygon 가스는 POL → POL/USD 사용. ETH/USD 넣으면 수천배 오차.

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Polygon mainnet CCIP router — CONFIRM at:
// https://docs.chain.link/ccip/directory/mainnet/chain/polygon-mainnet
const POLYGON_CCIP_ROUTER = "0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe";
// Polygon mainnet POL/USD feed.
const POLYGON_POL_USD = "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0";

export default buildModule("MolePinDeployRemotePolygon", (m) => {
  const initialOwner = m.getAccount(0);
  const treasury = m.getParameter("treasury", m.getAccount(0));

  const remote = m.contract("MolePinRemote", [initialOwner]);
  const gateway = m.contract("MolePinBridgeGateway", [
    initialOwner,
    remote,
    POLYGON_CCIP_ROUTER,
    POLYGON_POL_USD,
    treasury,
  ]);

  // NOTE: scripts/register-cct.ts will deploy BurnMintTokenPool,
  // call remote.grantPoolRoles(pool), register in the Token Admin Registry,
  // and gateway.setDestChain(<peer selectors>, true).
  // 풀 배포·권한부여·레지스트리 등록·setDestChain은 스크립트에서.

  return { remote, gateway };
});
