# 멀티체인 오라클 & 확장 가이드

## 수수료 정책 (확정)
**모든 체인에서, 멀티체인 이동은 무조건 수수료.** 출발 체인의 native 가스토큰으로 $1어치(상한$5).
게이트웨이는 어느 EVM 체인에든 **동일 코드**로 배포, 배포 시 그 체인 주소만 주입.

## ⚠ 체인별 native/USD 오라클 — 가장 중요한 함정
게이트웨이 배포 시 `nativeUsdFeed` 에는 **그 체인의 가스토큰/USD** 를 넣어야 한다.
**Polygon 주의**: 가스가 ETH 아니라 POL → 반드시 POL/USD (ETH/USD 넣으면 수천배 오차!)

| 체인 | 가스토큰 | 넣을 피드 | 메인넷 주소 (배포 직전 공식 재확인 필수) |
|---|---|---|---|
| BSC | BNB | BNB/USD | 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE |
| Ethereum | ETH | ETH/USD | 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 |
| Polygon | **POL** | **POL/USD** | 공식 페이지 확인 (ETH/USD 0xF9680...는 쓰지 말 것) |
| Base | ETH | ETH/USD | 공식 페이지 확인 |
| Arbitrum | ETH | ETH/USD | 0x639F... (공식 페이지서 전체주소 확인) |
| Optimism | ETH | ETH/USD | 공식 페이지 확인 |

### 테스트넷
| 체인 | 피드 | 주소 |
|---|---|---|
| BSC Testnet | BNB/USD | 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526 |
| Polygon Amoy | POL/USD | 0x001382149eBa3441043c1c66972b4772963f5D43 |

**주소 확인처(배포 시점 최신):** https://docs.chain.link/data-feeds/price-feeds/addresses
- 피드는 deprecated 될 수 있음 → 배포 직전 반드시 공식 페이지에서 재확인
- decimals 는 코드가 동적으로 읽음(8/18 무관 안전). 단 주소만 정확하면 됨.

## 체인 확장 (EVM)
새 EVM 체인 추가 절차 (코드 수정 0):
1. 그 체인에 MolePinRemote.sol 배포
2. 그 체인에 BurnMintTokenPool(CCT 표준) 배포 → remote.grantPoolRoles(pool)
3. 그 체인에 MolePinBridgeGateway 배포 (initialOwner, MOL=remote, Router, nativeUsdFeed, treasury)
4. 각 게이트웨이에서 setDestChain(새체인 selector, true) — 양방향 등록
5. CCT Token Admin Registry 등록 + lane/rate limit 설정

## 비EVM 체인 (별도 트랙 — 로드맵 뒤)
EVM이 아니라 Solidity 안 됨. 각 체인 언어로 토큰·브릿지 새로 작성 + CCIP 지원여부 확인.
| 체인 | 언어 | 비고 |
|---|---|---|
| TON | FunC/Tact | 별도 작성 |
| Solana | Rust(Anchor) | 별도 작성 |
| Sui / Aptos | Move | 별도 작성 |
| World Chain | (EVM호환) | MolePinRemote 그대로 가능. 단 World ID 연동해야 의미 |

## 검증 완료 (멀티체인 수수료 수학)
BSC/Polygon/Base/Arbitrum + 18dec 가상피드 — 전부 정확히 $1어치 native 환산 확인.
상한 $5 작동 확인. decimals 동적 처리 확인.
