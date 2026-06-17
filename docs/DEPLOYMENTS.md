# Deployments

Mainnet deployment addresses for MolePin across all 7 supported EVM chains.

> **KO:** 7개 EVM 메인넷의 MolePin 배포 주소입니다.

---

## Shared addresses

Thanks to CREATE2 and an identical remote-token address, several contracts deploy to the **same address on every chain**:

| Contract | Address | Chains |
|---|---|---|
| **Gateway** | `0x6942cb929de1e5747A3Ed72c7bD698f2aEdD3a55` | all 7 |
| **MolePinRemote** | `0x6942c0fD0d4655Ba8ee1251E204103AADb6Fee20` | 6 remote |
| **BurnMint pool** | `0xee89111388f3bead196f36f95ed997269ed0bab6` | 6 remote |

> **KO:** CREATE2 + 동일 리모트 토큰 주소 덕분에 게이트웨이(7체인)·리모트 토큰(6체인)·BurnMint 풀(6체인)은 모든 체인에서 동일 주소입니다.

---

## Home chain (BSC)

| Contract | Address |
|---|---|
| MolePin (home token) | `0x6942E2bb91b1C0Efaae67f03DBAB611107fBBd80` |
| LockRelease pool | `0x36aa3d0700e7bf8a91b9353ab51423abb628b581` |
| Gateway | `0x6942cb929de1e5747A3Ed72c7bD698f2aEdD3a55` |

---

## Per-chain matrix

| Chain | Chain ID | CCIP chain selector | Token | Pool type |
|---|---|---|---|---|
| **BNB Smart Chain** (home) | 56 | `11344663589394136015` | `0x6942E2bb…BBd80` | LockRelease |
| Ethereum | 1 | `5009297550715157269` | `0x6942c0fD…Fee20` | BurnMint |
| Polygon | 137 | `4051577828743386545` | `0x6942c0fD…Fee20` | BurnMint |
| Arbitrum One | 42161 | `4949039107694359620` | `0x6942c0fD…Fee20` | BurnMint |
| OP Mainnet | 10 | `3734403246176062136` | `0x6942c0fD…Fee20` | BurnMint |
| Base | 8453 | `15971525489660198786` | `0x6942c0fD…Fee20` | BurnMint |
| Avalanche C-Chain | 43114 | `6433500567565415381` | `0x6942c0fD…Fee20` | BurnMint |

The gateway is `0x6942cb929de1e5747A3Ed72c7bD698f2aEdD3a55` and the remote BurnMint pool is `0xee89111388f3bead196f36f95ed997269ed0bab6` on every chain above (except the home pool, which is the BSC LockRelease pool listed under Home chain).

> **KO:** 위 모든 체인에서 게이트웨이는 `0x6942cb…3a55`, 리모트 BurnMint 풀은 `0xee8911…0bab6`입니다(홈 풀만 BSC LockRelease로 별도).

---

## Topology

All 42 lanes (7 chains × 6 destinations) are wired and operational. Every transfer direction runs automatically:

- Home → remote (BurnMint mint)
- Remote → home (LockRelease release)
- Remote → remote (direct burn→mint mesh)

> **KO:** 42개 레인(7체인 × 6목적지) 전부 와이어링·작동. 모든 방향(홈→리모트, 리모트→홈, 리모트→리모트 직접)이 자동 실행됩니다.

---

## Notes

- Chain selectors are the canonical Chainlink CCIP identifiers; verify against the [CCIP Directory](https://docs.chain.link/ccip/directory) before integrating.
- Addresses above are mainnet. Always confirm on a block explorer before interacting.

> **KO:** selector는 Chainlink CCIP 공식 식별자입니다(연동 전 CCIP Directory에서 확인 권장). 위 주소는 메인넷이며, 상호작용 전 익스플로러에서 확인하세요.
