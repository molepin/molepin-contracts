# Tokenomics

> **KO:** MolePin의 공급, 수수료, 분배 모델을 설명합니다.

---

## Supply

| Property | Value |
|---|---|
| Genesis supply | **6,942,420,888,888 MOL** |
| Decimals | 18 |
| Max supply | Fixed at genesis (no mint path beyond it) |
| Home chain | BSC — full supply minted once at deployment |
| Remote chains | Start at 0; circulating supply tracks BSC-locked amount 1:1 |

The genesis supply is the permanent ceiling. The home token has **no `mint` function**; remote tokens can only mint/burn via the CCT pool (`MINTER_ROLE` / `BURNER_ROLE`). Holders may voluntarily burn their own balance (`ERC20Burnable`), which can only reduce supply, never raise it.

The cross-chain invariant — `BSC-locked == Σ remote circulating` — guarantees the ecosystem-wide total is always exactly the genesis supply, regardless of how MOL is distributed across chains.

> **KO:** 창세기 공급 6.94T가 영구 상한입니다. 홈은 mint 함수 없음, 리모트는 CCT 풀만 발행/소각. 보유자 자발적 소각만 가능(감소만). "BSC 잠금 = 리모트 유통 합" 불변식으로 총량이 항상 창세기 공급과 일치합니다.

---

## Bridge fees

A bridge transfer incurs two separate native-token costs on the source chain:

1. **CCIP protocol fee** — paid to the Chainlink router. Set by the protocol; varies by route and network conditions.
2. **MolePin fee** — a USD-denominated amount converted to native gas at send time, paid to the treasury:

   ```
   molepinFee_native = feeUsd × 10^feedDecimals / nativePrice
   ```

`feeUsd` is owner-configurable up to a hard cap (`MAX_FEE_USD`) and is set **per source chain**. Because native token prices differ widely (e.g. BNB vs POL), a flat USD fee can feel heavy on chains with a cheap native token. MolePin therefore uses a **tiered policy**:

| Source chain group | feeUsd |
|---|---|
| Expensive-gas main-liquidity chains (BSC, Ethereum) | higher tier |
| Low-cost L2s (Polygon, Base, Arbitrum, Optimism, Avalanche) | lower tier |

The user always pays fees in native gas — never in MOL. `quoteBridgeNative` returns the exact total to attach as `msg.value`, and any surplus is refunded by the contract.

> **KO:** 브리지 전송은 출발 체인에서 두 가지 네이티브 비용이 발생합니다 — CCIP 프로토콜 수수료(라우터)와 MolePin 수수료(USD를 네이티브로 환산, 트레저리 수취). feeUsd는 상한 내 owner 설정이며 출발 체인별로 둡니다. 네이티브 가격 차이가 커서, 비싼 메인 체인은 높게·싼 L2는 낮게 차등합니다. 수수료는 항상 네이티브로 지불(MOL 아님), 초과분은 환불됩니다.

---

## Distribution

The entire genesis supply is minted to the deployer/owner address at deployment. Distribution, reserves, and liquidity provisioning are performed afterward via plain ERC20 transfers — the token contract has no special allocation or vesting logic baked in, preserving its purity.

> **KO:** 창세기 전량은 배포 시 owner에게 발행됩니다. 분배·리저브·유동성 공급은 이후 일반 transfer로 수행하며, 토큰에 별도 배분/베스팅 로직을 넣지 않아 순수성을 유지합니다.

---

## Treasury & ownership

- **Treasury** — receives the MolePin native fee. Owner-settable.
- **Ownership** — `Ownable2Step` (two-step transfer to prevent mistakes/hijack). Migration to a Safe multisig / timelock is on the roadmap. The owner's powers are limited to configuration (fees, treasury, routes, gas limit) and cannot affect supply, balances, or user transfers.

> **KO:** 트레저리는 MolePin 네이티브 수수료를 수취(owner 설정). 소유권은 2단계 이전, 멀티시그 이전 예정. owner 권한은 설정(수수료·트레저리·경로·가스 한도)에 한정되며 공급·잔고·전송에 영향을 줄 수 없습니다.
