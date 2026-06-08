# MolePin: CCT → LayerZero OFT 변환 매핑

CCT 게이트웨이 설계를 LayerZero OFT mesh로 재구현하면서 **무엇을 보존·변경·삭제·신규 작성**했는지 정리한 문서. 기준 철학은 동일하다: *토큰은 순수하게, 모든 정책(특히 native fee)은 게이트웨이에.*

---

## 1. 컴포넌트 매핑

| CCT 모델 | LayerZero OFT 모델 | 상태 |
|---|---|---|
| `MolePin.sol` (BSC 홈, 6.94T 고정) | `MolePin.sol` 그대로 + `MolePinOFTAdapter` 가 lock | **보존** |
| `MolePinRemote.sol` (BurnMint, 0-start) | `MolePinOFT.sol` (mint/burn, 0-start) | **대체** (이미 작성됨) |
| BSC `LockReleaseTokenPool` | `MolePinOFTAdapter` (lockbox) | **대체** (이미 작성됨) |
| 리모트 `BurnMintTokenPool` | `MolePinOFT` 내장 `_credit`/`_debit` | **대체** (풀이 토큰에 흡수됨) |
| `MolePinBridgeGateway` (송신+수신) | `MolePinBridgeGatewayLZ` (송신 전용) | **변경** (신규 작성) |
| `ccipReceive()` (수신 게이트웨이) | — (OFT `_credit` 이 유저에 직접 mint) | **삭제** |
| `trustedRemoteGateway` 매핑 | OFT `peers` (setPeer) | **삭제** → 프로토콜로 이전 |
| CCIP Router `getFee`/`ccipSend` | OFT `quoteSend`/`send` | **변경** |
| `MockCCIPRouter` / `MockPriceOracle` | LZ EndpointV2 Mock + 오라클 Mock | **신규 필요** (테스트용) |

---

## 2. 보존된 설계 (CCT에서 그대로 가져온 것)

- **native fee 철학**: 비즈니스 수수료를 native 토큰으로, 게이트웨이에서 한 트랜잭션에 징수. CCT 게이트웨이의 핵심 의도였고 LZ 게이트웨이가 정확히 계승.
- **오라클 기반 $ 고정 fee** (BSC): `molepinFeeUsdFixed()` = CCT의 `molepinFeeInNative()` 와 산식 동일. $5 cap, 1시간 staleness 체크 그대로.
- **configure 패턴**: 생성자는 `(owner, treasury)` 만, 체인별 주소(OFT/oracle/mode)는 post-deploy `configure()` 주입. 한 번만(`require(!configured)`).
- **treasury / $5 cap / 환불 로직 / sweepNative**: 동일.
- **NatSpec 영문 primary + KO 아사이드**: 문서화 규율 유지.

## 3. 변경된 설계

| 항목 | CCT | LayerZero | 이유 |
|---|---|---|---|
| fee 모드 | 단일 ($1 고정) | **2모드** (USD_FIXED / LZ_MULTIPLE) | 리모트는 lzFee 2배 정책 |
| 수신자(`to`) | 게이트웨이 주소 (forward) | **최종 유저 주소 직접** | OFT는 _credit이 유저에 직접 mint |
| fee 견적 | `ROUTER.getFee` | `OFT.quoteSend(sp, false)` | false=native 결제 |
| 전송 | `ROUTER.ccipSend{value}` | `OFT.send{value: lzFee}` | 시그니처 다름 (SendParam/MessagingFee/refund) |
| gas 제어 | `extraArgs.gasLimit`(250k) | `extraOptions`(lzReceiveOption) | LZ는 옵션 bytes로 |
| 체인 식별 | `uint64` chain selector | `uint32` dstEid | LZ endpoint id |

## 4. 삭제된 설계 (LZ에서 불필요)

- **수신 게이트웨이 / `ccipReceive` 전체**: CCT는 EOA 90k 가스 한도 때문에 "게이트웨이로 받아 forward" 가 필수였음. OFT는 `_credit`이 유저에게 직접 mint하고 수신 가스를 `lzReceiveOption`으로 제어 → 수신 게이트웨이 불필요. **CCT의 가장 복잡했던 부분(TokenHandlingError, Tenderly 추적)이 통째로 사라짐.**
- **CREATE2 same-address 강박**: 수신자가 게이트웨이가 아니므로 체인마다 게이트웨이 주소가 달라도 무방. (V3의 2-arg constructor 패턴 자체는 깔끔하니 유지하나, 강제 요건은 아님.)
- **`trustedRemoteGateway` 검증**: 발신자 진위는 OFT `peers`(setPeer)가 프로토콜 레벨에서 강제. 게이트웨이 레벨 검증 불필요.
- **`supportsInterface` (IAny2EVMMessageReceiver)**: 수신자가 아니므로 불필요.

## 5. 보안 모델 차이 (중요)

CCT는 게이트웨이가 수신자였기에 `trustedRemoteGateway` + router 검증을 **게이트웨이 레벨**에서 했다.
LZ는 발신자 검증이 **프로토콜 레벨**(`peers` 매핑)로 내려간다. 이건 LayerZero 표준 모델이라 안전하지만, 운영상 함의:

- `setPeer(eid, oft_address)` 설정이 **보안 크리티컬**. 잘못 설정하면 위조 메시지 수신 가능.
- DVN 2-Required 독립 설정(layerzero.config)이 실제 신뢰 경계. 컨트랙트 밖 운영 영역.
- OFT 코드의 pause/blocklist/RateLimiter 가 추가 방어선.

## 6. 미해결 / 다음 단계

- [ ] **LZ EndpointV2 Mock 기반 테스트 스위트** — CCT의 33개 테스트에 대응. fee 두 모드, 단일 트랜잭션 원자성, 환불, 오라클 staleness, dstEid allowlist.
- [ ] **extraOptions 빌더** — `lzReceiveOption` gas 값 결정 (CCT의 250k 대응). 프론트/스크립트에서 생성.
- [ ] **TON 측**: 본 게이트웨이는 EVM 전용. TON은 LayerZero OFT가 별도 트랙(FunC/Tact)이라 TON Jetton + TON OFT 어댑터는 신규 작성 필요. ★ 본 EVM 게이트웨이 검증 후 착수.
- [ ] **owner = 타임락+멀티시그** 전환 (메인넷 전).
- [ ] 외부 감사 — OFT 코드 주석의 AUDIT 체크리스트 + 게이트웨이.
