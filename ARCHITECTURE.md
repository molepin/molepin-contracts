# MolePin Architecture

This document explains the design decisions behind the MolePin contracts —
not just *what* they do, but *why* they are built this way.

<details><summary>▶ 한국어로 보기</summary>

이 문서는 MolePin 컨트랙트의 설계 결정을 설명합니다 — 무엇을 하는지뿐 아니라
*왜* 이렇게 만들었는지까지.

</details>

---

## Design principles

Five principles govern every contract decision:

1. **Regulation as a premise, not something to bypass.** We design to pass, not to evade.
2. **Break cartels, keep rules.** Decentralized and transparent, verified on-chain.
3. **Users first, finance later.** The token and game come first; redemption/collateral are separate, later modules.
4. **Expandable, but narrow now.** Leave hooks; build only what is needed today.
5. **Buildable units.** Big vision, one finishable piece at a time.

<details><summary>▶ 한국어로 보기</summary>

다섯 가지 원칙이 모든 컨트랙트 결정을 지배합니다:

1. **규제는 우회 대상이 아니라 전제.** 회피가 아니라 통과하도록 설계.
2. **카르텔은 깨되 규칙은 지킨다.** 탈중앙·투명, 온체인 검증.
3. **유저 먼저, 금융은 나중.** 토큰·게임이 먼저, 환금·담보는 별도의 나중 모듈.
4. **확장 가능하되 지금은 좁게.** 훅은 남기고, 오늘 필요한 것만.
5. **완성 가능한 단위.** 비전은 크게, 구현은 한 번에 끝낼 수 있는 조각으로.

</details>

---

## Three contracts

### MolePin.sol — home token (BSC)

A pure, immutable ERC20. The entire supply (6,942,420,888,888 MOL) is minted
once at deployment. There is **no mint function** anywhere, so supply can never
increase — `GENESIS_SUPPLY` is a permanent ceiling, like Bitcoin's 21M. Only
voluntary self-burn can reduce it.

No transfer fee, no blacklist, no pause, no rebase. This purity is deliberate:
it keeps the token friendly to DEX listing (PancakeSwap/Uniswap) and to the
Chainlink CCT pool. All policy (fees, discounts, staking, rewards) lives in
**separate modules** that reference the token — the token itself never changes.

<details><summary>▶ 한국어로 보기</summary>

순수·불변 ERC20. 전체 발행량(6,942,420,888,888 MOL)을 배포 시 한 번 발행합니다.
**mint 함수가 어디에도 없어** 공급이 절대 증가하지 않습니다 — `GENESIS_SUPPLY`는
비트코인 2,100만처럼 영구 상한입니다. 자발적 자기 소각만 줄일 수 있습니다.

전송 수수료·블랙리스트·pause·rebase 없음. 이 순수성은 의도된 것으로, DEX 상장과
Chainlink CCT 풀 호환성을 지킵니다. 모든 정책(수수료·할인·스테이킹·보상)은 토큰을
참조하는 **별도 모듈**에 있고, 토큰 자체는 변하지 않습니다.

</details>

### MolePinRemote.sol — remote token (other EVM chains)

On chains other than BSC, MOL exists as `MolePinRemote`. It starts at **zero
supply**. Only the Chainlink CCT `BurnMintTokenPool` (granted `MINTER_ROLE` /
`BURNER_ROLE` via `grantPoolRoles`) can mint or burn. No human can mint freely.

Remote circulating supply always matches the amount locked in the BSC
`LockReleaseTokenPool`, 1:1, enforced by CCT. So total ecosystem supply stays
fixed at the BSC 6.94T — a remote mint is not new issuance, just a
representation of BSC-locked tokens on another chain. Immutability is preserved
across all chains.

<details><summary>▶ 한국어로 보기</summary>

BSC가 아닌 체인에서 MOL은 `MolePinRemote`로 존재합니다. **0 공급에서 시작**합니다.
Chainlink CCT `BurnMintTokenPool`(`grantPoolRoles`로 권한 부여됨)만 mint/burn할 수
있습니다. 사람이 임의로 발행할 수 없습니다.

리모트 유통량은 BSC `LockReleaseTokenPool`에 잠긴 양과 항상 1:1로 일치하며 CCT가
강제합니다. 따라서 전체 생태계 공급은 BSC 6.94조로 고정 — 리모트 mint는 새 발행이
아니라 BSC에 잠긴 토큰의 다른 체인 표현입니다. 모든 체인에서 불변성이 유지됩니다.

</details>

### MolePinBridgeGateway.sol — cross-chain transfer + fee

The single front door for cross-chain transfers. Same code deploys to any EVM
chain; per-chain addresses (MOL, CCIP Router, native/USD feed, treasury) are
injected at deployment.

Every cross-chain transfer is charged a fee, on every chain. The fee is the
**source chain's native gas token worth $1** (BNB on BSC, POL on Polygon, ETH
on Base/Arbitrum/Optimism), computed via the chain's Chainlink native/USD feed.
It is owner-adjustable but hard-capped at $5 (`MAX_FEE_USD`, immutable), and is
sent to the treasury. The token itself is never touched — the bridged amount
arrives intact. CCIP's own fee (gas + premium) is paid separately to the router.

Why a gateway instead of charging in the pool: routing all transfers through one
contract makes the fee unavoidable while leaving the CCT pools as Chainlink
standard, which keeps the audit surface small.

<details><summary>▶ 한국어로 보기</summary>

멀티체인 이동의 유일한 정문. 동일 코드가 어느 EVM 체인에든 배포되고, 체인별 주소
(MOL, CCIP 라우터, native/USD 피드, treasury)를 배포 시 주입합니다.

모든 멀티체인 이동에 모든 체인에서 수수료를 징수합니다. 수수료는 **출발 체인의 native
가스토큰으로 $1어치**(BSC→BNB, Polygon→POL, Base/Arbitrum/Optimism→ETH)이며, 그 체인
Chainlink native/USD 피드로 계산합니다. owner 조정 가능하되 상한 $5(`MAX_FEE_USD`,
불변)이며 treasury로 전송됩니다. 토큰 자체는 건드리지 않아 보낸 양이 그대로 도착합니다.
CCIP 자체 수수료(가스+프리미엄)는 라우터에 별도로 지불됩니다.

풀이 아닌 게이트웨이로 수수료를 받는 이유: 모든 이동을 한 컨트랙트로 모으면 수수료가
우회 불가능해지고, CCT 풀은 Chainlink 표준 그대로 두어 감사 범위가 작아집니다.

</details>

---

## Multichain architecture (CCT)

MolePin uses **Chainlink CCT (Cross-Chain Token) over CCIP**, not a custom bridge.

This is a deliberate trust decision. Cross-chain bridges are historically the
most-exploited part of crypto (Ronin $600M, Wormhole $320M, Nomad $190M). A
custom bridge is buildable, but proving "it won't be drained" takes years and
audits, and one hack ends the project. CCIP's fee buys not a router, but
Chainlink's risk-management network, multi-year track record, and accountability.
We chose verified infrastructure over reinventing it.

- **Home (BSC)**: `LockReleaseTokenPool` (locks/releases the original 6.94T).
- **Remote**: `BurnMintTokenPool` (mints on arrival, burns on return).
- Both pools are Chainlink standard, deployed as-is. Only the gateway is custom.

<details><summary>▶ 한국어로 보기</summary>

MolePin은 자체 브릿지가 아니라 **CCIP 기반 Chainlink CCT**를 사용합니다.

이는 의도된 신뢰 결정입니다. 크로스체인 브릿지는 역사상 가장 많이 털린 영역입니다
(Ronin $600M, Wormhole $320M, Nomad $190M). 자체 브릿지는 만들 수 있지만 "안 털린다"를
증명하는 데 수년과 감사가 필요하고, 한 번의 해킹으로 프로젝트가 끝납니다. CCIP 수수료는
라우터가 아니라 Chainlink의 리스크 관리 네트워크·수년 무사고 실적·책임성을 사는 것입니다.
재발명보다 검증된 인프라를 택했습니다.

- **홈(BSC)**: `LockReleaseTokenPool` (원본 6.94조 잠금/해제)
- **리모트**: `BurnMintTokenPool` (도착 시 mint, 복귀 시 burn)
- 두 풀 모두 Chainlink 표준 그대로 배포. 게이트웨이만 커스텀.

</details>

---

## Adding a new chain

EVM chains expand with **no code change**: deploy `MolePinRemote` + the standard
pool + the gateway (inject that chain's addresses), call `grantPoolRoles`,
register in the CCT Token Admin Registry, and `setDestChain` both directions.

Non-EVM chains (TON, Solana, Sui/Aptos) are a separate track — they require
re-implementation in their own languages (FunC/Tact, Rust, Move) and are on the
roadmap, not in this repo. World Chain is EVM-compatible and works as a remote
as-is (a World ID integration would make it meaningful).

<details><summary>▶ 한국어로 보기</summary>

EVM 체인은 **코드 수정 없이** 확장됩니다: `MolePinRemote` + 표준 풀 + 게이트웨이 배포
(그 체인 주소 주입), `grantPoolRoles` 호출, CCT Token Admin Registry 등록, `setDestChain`
양방향.

비EVM 체인(TON, Solana, Sui/Aptos)은 별도 트랙으로, 각 언어(FunC/Tact, Rust, Move)로
재구현이 필요하며 로드맵에 있습니다. World Chain은 EVM 호환이라 리모트로 그대로
동작합니다(World ID 연동 시 의미가 생깁니다).

</details>

---

## Testing

30 unit + integration tests cover: token immutability (no mint, pure ERC20),
fee math ($1 worth of native across chains, $5 cap, dynamic decimals), oracle
safety (zero/stale price reverts), access control (owner/role-gated), the full
`bridge()` value flow (fee to treasury, excess refund), and remote mint/burn
permissions. Run with `npm test`.

<details><summary>▶ 한국어로 보기</summary>

30개의 단위·통합 테스트가 다음을 검증합니다: 토큰 불변성(mint 없음, 순수 ERC20),
수수료 수학(체인 전반 $1어치 native, $5 상한, decimals 동적), 오라클 안전(0/오래된 가격
revert), 접근 제어(owner/역할 제한), `bridge()` 전체 자금 흐름(treasury 전달, 초과 환불),
리모트 mint/burn 권한. `npm test`로 실행.

</details>
