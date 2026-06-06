# MolePin Contracts

> The first meme that doesn't bark — it digs. A BSC-native MemeFi token with Chainlink CCT multichain bridging. The core is a pure, immutable ERC20; all policy (fees, staking, rewards) lives in separate modules.

<details><summary>▶ 한국어로 보기</summary>

짖지 않는 첫 번째 밈 — 땅을 판다. BSC를 홈 체인으로 하는 MemeFi 토큰이며 Chainlink CCT로 멀티체인 이동을 지원합니다. 코어는 순수·불변 ERC20이고, 모든 정책(수수료·스테이킹·보상)은 별도 모듈에 둡니다.

</details>

---

## Status

Pre-deployment. Contracts compiled & verified locally (Solidity 0.8.28, viaIR, Cancun).

<details><summary>▶ 한국어로 보기</summary>

배포 전. 컨트랙트 로컬 컴파일·검증 완료 (Solidity 0.8.28, viaIR, Cancun).

</details>

## Contracts

| Contract | Role | Chain |
|---|---|---|
| `MolePin` | Home token — pure, immutable, 6,942,420,888,888 MOL | BSC |
| `MolePinRemote` | Remote token — pool-only mint/burn, starts at 0 | Polygon / Base / Arbitrum / Optimism / ... |
| `MolePinBridgeGateway` | Cross-chain transfer + fee (native gas token, $1, cap $5) | every EVM chain |

CCT pools (`LockReleaseTokenPool` on BSC, `BurnMintTokenPool` on remotes) are Chainlink standard and deployed as-is.

<details><summary>▶ 한국어로 보기</summary>

| 컨트랙트 | 역할 | 체인 |
|---|---|---|
| `MolePin` | 홈 토큰 — 순수·불변, 6,942,420,888,888 MOL | BSC |
| `MolePinRemote` | 리모트 토큰 — 풀 전용 mint/burn, 0에서 시작 | Polygon / Base / Arbitrum / Optimism / ... |
| `MolePinBridgeGateway` | 멀티체인 이동 + 수수료 (native 가스토큰, $1, 상한 $5) | 모든 EVM 체인 |

CCT 풀(BSC는 `LockReleaseTokenPool`, 리모트는 `BurnMintTokenPool`)은 Chainlink 표준을 그대로 사용합니다.

</details>

## Tokenomics

- **Supply**: 6,942,420,888,888 MOL (fixed, 18 decimals). No mint function — supply can never increase; voluntary burn only.
- **Home**: BSC (LockRelease). **Remotes**: BurnMint, 1:1 with the BSC-locked amount (CCT-enforced).
- **Bridge fee**: every cross-chain transfer is charged the source chain's native gas token worth $1 (owner-adjustable, hard-capped $5), paid to treasury. CCIP's own fee is separate. MOL itself is never touched.

<details><summary>▶ 한국어로 보기</summary>

- **발행량**: 6,942,420,888,888 MOL (고정, 18 decimals). mint 함수 없음 — 공급은 절대 증가하지 않으며 자발적 소각만 가능.
- **홈**: BSC(LockRelease). **리모트**: BurnMint, BSC에 잠긴 양과 1:1 (CCT가 강제).
- **브릿지 수수료**: 모든 멀티체인 이동에 출발 체인의 native 가스토큰으로 $1어치(owner 조정 가능, 상한 $5)를 징수하여 배포지갑으로 보냅니다. CCIP 자체 수수료는 별도이며, MOL 자체는 건드리지 않습니다.

</details>

## Quick Start

```bash
npm install
npx hardhat compile
npm test
```

Deploy (home first):
```bash
npx hardhat ignition deploy ignition/modules/MolePinDeployHome.ts --network bscTestnet
npx hardhat ignition deploy ignition/modules/MolePinDeployHome.ts --network bsc
# remote chains
npx hardhat ignition deploy ignition/modules/MolePinDeployRemote.ts --network polygon
```

## Adding a new EVM chain (no code change)

1. Deploy `MolePinRemote` on the new chain.
2. Deploy `BurnMintTokenPool` (CCT standard) → `remote.grantPoolRoles(pool)`.
3. Deploy `MolePinBridgeGateway` (inject that chain's MOL / Router / native-USD feed / treasury).
4. `setDestChain(selector, true)` on every gateway — register both directions.
5. Register in the CCT Token Admin Registry + configure lanes / rate limits.

See `DEPLOY_NOTES.md` and `ORACLE_CHAINS.md`.

<details><summary>▶ 한국어로 보기</summary>

## 새 EVM 체인 추가 (코드 수정 없음)

1. 새 체인에 `MolePinRemote` 배포.
2. `BurnMintTokenPool`(CCT 표준) 배포 → `remote.grantPoolRoles(pool)`.
3. `MolePinBridgeGateway` 배포 (그 체인의 MOL / Router / native-USD 피드 / treasury 주입).
4. 모든 게이트웨이에서 `setDestChain(selector, true)` — 양방향 등록.
5. CCT Token Admin Registry 등록 + lane / rate limit 설정.

`DEPLOY_NOTES.md`와 `ORACLE_CHAINS.md` 참고.

</details>

## Tech Stack

Solidity 0.8.28 · Hardhat 3 · viem · OpenZeppelin 5.x · Chainlink CCT (CCIP) + Data Feeds · BNB Chain (home).

## Security

Smart-contract changes touching state, fees, or access control require design discussion first. Do **not** open public issues for vulnerabilities — see `SECURITY.md`.

<details><summary>▶ 한국어로 보기</summary>

state, 수수료, 권한에 영향을 주는 컨트랙트 변경은 사전 설계 논의가 필요합니다. 보안 취약점은 공개 이슈로 열지 마세요 — `SECURITY.md` 참고.

</details>

## License

MIT
