# Architecture

This document describes how MolePin moves MOL across chains while preserving a fixed total supply.

> **KO:** 이 문서는 MolePin이 고정 총공급을 유지하면서 MOL을 체인 간 이동시키는 방식을 설명합니다.

---

## 1. Supply model

MolePin has exactly one source of truth for supply: the **BSC home chain**, where the full genesis supply of 6,942,420,888,888 MOL is minted once and never increased.

- **Home (BSC)** — `MolePin.sol` holds the original supply. A **LockRelease** CCT pool locks MOL when it bridges out and releases it when it bridges back. No minting.
- **Remote (Ethereum, Polygon, Arbitrum, Optimism, Base, Avalanche)** — `MolePinRemote.sol` starts at **0 supply**. A **BurnMint** CCT pool mints the bridged amount on arrival and burns it on departure.

The invariant: at any moment,

```
locked_in_BSC_pool  ==  Σ (circulating supply on every remote chain)
```

so the ecosystem-wide total always equals the BSC genesis supply. Remote mints are **not new issuance** — they are a 1:1 representation of MOL locked on BSC, enforced by Chainlink CCT.

> **KO:** 공급의 단일 진실은 BSC입니다. 홈은 LockRelease(잠금/해제), 리모트는 BurnMint(도착 시 발행/출발 시 소각). "BSC 풀에 잠긴 양 = 모든 리모트 유통량 합"이 항상 성립하여 총량이 고정됩니다. 리모트 발행은 새 발행이 아니라 BSC 잠금분의 1:1 표현입니다.

---

## 2. Token-pure / policy-in-gateway

The MOL token contracts are deliberately minimal ERC20s:

- No transfer fee, no max-tx/max-wallet limit, no blacklist, no pause, no rebase.
- `ERC20Permit` (EIP-2612) for gasless approvals; `ERC20Burnable` for voluntary self-burns only.
- The owner cannot mint (home), cannot touch balances, and cannot alter transfers.

All cross-chain behaviour — fees, trusted routes, gas budgeting, recipient forwarding — lives in a separate **gateway** contract. This separation keeps the token frictionless for DEX listing (PancakeSwap/Uniswap) and CCT pool compatibility, and means the token can never be the source of a bridge bug.

> **KO:** 토큰은 의도적으로 최소 ERC20입니다(수수료·한도·블랙리스트·pause·rebase 없음). 모든 크로스체인 정책은 게이트웨이에 분리되어, DEX 상장·CCT 호환을 해치지 않고 토큰이 브리지 버그의 원인이 될 수 없습니다.

---

## 3. The gateway

`MolePinBridgeGateway.sol` wraps Chainlink CCT to provide:

1. **Native-token fees.** The gateway quotes and collects a fee in the source chain's native gas token (BNB, ETH, POL, AVAX…), sized from a USD target via a Chainlink native/USD price feed. The fee is paid to a treasury address; the user never pays MOL.
2. **Trusted routing.** Each gateway stores the trusted destination gateway per chain selector and the set of allowed destination chains. Messages are only accepted from trusted source gateways.
3. **Gateway-as-receiver.** The CCIP message's receiver is the **destination gateway** (a contract), not the user. The user's address travels in the message `data`. On arrival, the destination gateway's `ccipReceive` forwards the minted/released MOL to the real user.
4. **Same address everywhere.** Deployed via CREATE2 to an identical address on all 7 chains, which (together with an identical remote-token address) yields identical pool and gateway addresses across chains.

### Send path (`bridge`)

```
user → gateway.bridge(destSelector, recipient, amount) {value: nativeFee}
     → gateway pulls MOL from user, approves the CCIP router
     → router.ccipSend → source pool locks (BSC) or burns (remote)
     → molepinFee paid to treasury; surplus native refunded to user
```

### Receive path (`ccipReceive`)

```
CCIP router/offramp → destination pool mints (remote) or releases (BSC) to the gateway
                    → gateway.ccipReceive forwards `amount` to the recipient in message.data
```

> **KO:** 게이트웨이는 (1) 네이티브 수수료(USD 목표를 Chainlink 피드로 환산, 트레저리 수취), (2) 신뢰 경로(체인별 신뢰 게이트웨이/허용 체인), (3) 수신자=게이트웨이(유저 주소는 data에, ccipReceive가 forward), (4) CREATE2 동일 주소를 제공합니다.

---

## 4. Fee model

The MolePin fee is a USD-denominated amount converted to native at send time:

```
molepinFee_native = feeUsd × 10^feedDecimals / nativePrice
```

`feeUsd` is owner-settable up to a hard `MAX_FEE_USD` cap and is set **per source chain**, because the fee is collected on the chain the transfer originates from. This allows a tiered policy: a higher fee on expensive-gas main-liquidity chains, a lower fee on cheap L2s where small transfers are frequent. See [`TOKENOMICS.md`](TOKENOMICS.md).

The CCIP protocol fee is separate and goes to the Chainlink router. `quoteBridgeNative` returns the exact total to send as `msg.value`; any surplus is refunded.

> **KO:** MolePin 수수료는 USD 목표를 전송 시점 네이티브로 환산합니다. feeUsd는 상한 내에서 owner가 출발 체인별로 설정 — 비싼 메인 체인은 높게, 싼 L2는 낮게 차등 가능. CCIP 프로토콜 수수료는 별도(라우터). quoteBridgeNative가 정확한 총액을 반환하고 초과분은 환불됩니다.

---

## 5. Destination execution

Cross-chain token arrival runs inside Chainlink's offramp under a tight gas budget. To keep automatic execution reliable, the gateway:

- Sets an explicit destination gas limit for the `ccipReceive` callback so forwarding always has enough gas.
- Is initialized so that the token-handling step on the destination fits within CCT's release/mint gas budget. Concretely, the gateway's token balance slot is warmed once per chain, after which mint/release writes stay inexpensive and automatic execution succeeds without manual intervention.

This warming is a one-time, per-chain initialization performed as part of onboarding a chain; it requires no contract change and is permanent thereafter. The specific operational steps are kept in the project's internal runbook.

> **KO:** 목적지 토큰 수신은 Chainlink 오프램프의 타이트한 가스 예산 안에서 실행됩니다. 게이트웨이는 ccipReceive 콜백 가스 한도를 명시하고, 체인별로 토큰 잔액 슬롯을 1회 워밍하여 mint/release 쓰기 비용을 낮춰 자동 실행이 수동 개입 없이 성공하도록 합니다. 이 워밍은 체인 온보딩 시 1회성·영구 초기화이며, 컨트랙트 변경이 필요 없습니다. 구체적 운영 절차는 내부 런북에 둡니다.

---

## 6. Transfer time

End-to-end transfer time is dominated by **source-chain finality**, since CCIP waits for the origin block to finalize before delivering. Fast-finality chains (e.g. BSC) deliver in 1–2 minutes; slower-finality chains (e.g. Polygon) can take 14–16 minutes. This is normal protocol behaviour, not a failure.

> **KO:** 전송 시간은 출발 체인 finality에 좌우됩니다(BSC 1~2분, Polygon 14~16분). 이는 정상 동작입니다.

---

## 7. Topology

All transfer directions are supported and operate automatically:

- **Home → remote** (BSC → any remote): BurnMint mint.
- **Remote → home** (any remote → BSC): LockRelease release.
- **Remote → remote** (any remote → any remote): burn on source, mint on destination — a direct mesh route that does not pass through the home chain.

> **KO:** 모든 방향이 자동 동작합니다 — 홈→리모트(mint), 리모트→홈(release), 리모트→리모트(소스 burn·목적지 mint, 홈 경유 없이 직접). 풀메시.
