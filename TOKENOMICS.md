# MolePin Tokenomics

<details><summary>▶ 한국어로 보기</summary>

# MolePin 토크노믹스

</details>

## Supply

| Item | Value |
|---|---|
| Total supply | 6,942,420,888,888 MOL |
| Decimals | 18 |
| Mintable? | No — no mint function exists (permanent ceiling) |
| Burnable? | Yes — voluntary self-burn only |
| Home chain | BSC |

The number 6,942,420,888,888 is fixed forever. Without a mint function, supply
can only stay the same or decrease (via burn). This is the immutability
guarantee, comparable to Bitcoin's fixed cap.

<details><summary>▶ 한국어로 보기</summary>

| 항목 | 값 |
|---|---|
| 총 발행량 | 6,942,420,888,888 MOL |
| 소수점 | 18 |
| 추가 발행 | 불가 — mint 함수 없음 (영구 상한) |
| 소각 | 가능 — 자발적 자기 소각만 |
| 홈 체인 | BSC |

6,942,420,888,888이라는 수는 영원히 고정입니다. mint 함수가 없으므로 공급은 유지되거나
(소각으로) 감소만 합니다. 비트코인의 고정 상한과 같은 불변성 보장입니다.

</details>

## Cross-chain supply

Total supply is fixed at the BSC 6.94T. On remote chains, MOL is minted by the
Chainlink CCT pool only in 1:1 correspondence with the amount locked on BSC.
Remote mints are not new issuance — they represent BSC-locked tokens elsewhere.
Sum of (BSC circulating) + (all remote circulating) always equals what is not
locked, and total never exceeds 6.94T.

<details><summary>▶ 한국어로 보기</summary>

총 공급은 BSC 6.94조로 고정입니다. 리모트 체인에서 MOL은 BSC에 잠긴 양과 1:1로만
CCT 풀이 발행합니다. 리모트 mint는 새 발행이 아니라 BSC에 잠긴 토큰의 다른 곳 표현입니다.
(BSC 유통) + (전체 리모트 유통)의 합은 항상 잠기지 않은 양과 같고, 총량은 6.94조를 넘지
않습니다.

</details>

## Bridge fee

| Item | Value |
|---|---|
| When | Every cross-chain transfer, every chain |
| Amount | Source chain's native gas token worth $1 |
| Adjustable | Yes (owner), hard-capped at $5 (immutable) |
| Paid in | BNB / POL / ETH (source chain's gas token) |
| Recipient | Treasury |
| Touches MOL? | No — bridged amount arrives intact |

The fee is separate from and on top of CCIP's own fee. It is computed live via
each chain's Chainlink native/USD price feed. It is a secondary revenue stream
(cross-chain transfers are occasional); primary revenue is intended to come from
frequent activity (game, payments) in later modules.

<details><summary>▶ 한국어로 보기</summary>

| 항목 | 값 |
|---|---|
| 시점 | 모든 멀티체인 이동, 모든 체인 |
| 금액 | 출발 체인 native 가스토큰으로 $1어치 |
| 조정 | 가능(owner), 상한 $5(불변) |
| 결제 토큰 | BNB / POL / ETH (출발 체인 가스토큰) |
| 수취처 | Treasury |
| MOL 영향 | 없음 — 보낸 양 그대로 도착 |

수수료는 CCIP 자체 수수료와 별개로 그 위에 부과됩니다. 각 체인 Chainlink native/USD
피드로 실시간 계산됩니다. 부가 재원이며(멀티체인 이동은 간헐적), 주 재원은 이후 모듈의
빈번한 활동(게임·결제)에서 나올 예정입니다.

</details>

## What lives outside the token

By design, the token contract contains none of this. These are separate modules
(planned / partial) that reference MOL as a plain ERC20:

- Discounts / partner-token fee reductions
- Staking (variable revenue share, not guaranteed interest)
- Reward distribution (circulation without new issuance)
- Game economy

Keeping these out of the token preserves its purity and DEX/CCT compatibility,
and isolates regulatory surface to the modules that need it.

<details><summary>▶ 한국어로 보기</summary>

설계상 토큰 컨트랙트에는 이런 것이 전혀 없습니다. 아래는 MOL을 일반 ERC20으로 참조하는
별도 모듈(계획/일부)입니다:

- 할인 / 제휴 토큰 수수료 절감
- 스테이킹 (보장 이자가 아닌 변동 수익 공유)
- 보상 분배 (새 발행 없는 순환)
- 게임 경제

이를 토큰 밖에 두어 순수성과 DEX/CCT 호환성을 지키고, 규제 표면을 필요한 모듈로
국한합니다.

</details>
