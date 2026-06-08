// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { RateLimiter } from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/* ============================================================================
 *  MolePinOFT — REMOTE MINT/BURN TOKEN (BSC 외 모든 체인)  · v2 audit-candidate
 * ----------------------------------------------------------------------------
 *  ⚠ 미감사. 외부 감사 + 테스트넷 재검증 전 메인넷 배포 금지.
 *  제네시스 공급 0 (생성자 mint 없음). 공급은 오직 인바운드 브릿지 mint 로만
 *  증가, 아웃바운드 burn 으로만 감소 → 전 체인 합 ≤ GLOBAL_MAX_SUPPLY.
 *
 *  [v2 변경]
 *   · #5 fix — 블록리스트 _update 에서 sender(from) 한정 (이전 from&&to).
 *       mint(from=0)·인바운드 절대 안 막힘 → stuck 메시지/보존 위반 제거.
 *       blocked = 보낼 수 없음(동결), 받을 수는 있음.
 *   · #1/#2 — Emergency Pause: 글로벌+경로별(eid), guardian 비대칭.
 *       inbound pause 시 _credit revert → LZ v2 메시지 저장/재시도(손실 X).
 *   · ★ 보존-안전 브릿지 수수료(감사 1순위, v1 유지·강화):
 *       수수료분은 "소각하지 않고" 이 체인 collector 로 이동(공급 불변,
 *       재분배만). 크로싱분만 _burn → 도착 체인이 정확히 그만큼 mint.
 *       ∴ 이 체인 소각량 == 도착 mint량 (보존 I2). _debitView 도 동일 산식.
 *   · RateLimiter: opt-in. 미설정 eid 는 enforce 안 함(브릿지 brick 방지 —
 *       "설정 누락 시 전 송금 정지"는 운영 footgun). 설정된 경로만 한도 적용.
 *       ※ 감사 논점: 기본값을 "무제한(opt-in)" vs "설정 전 금지(secure-by-
 *         default)" 중 어느 쪽으로 둘지는 감사+운영이 최종 결정. 현재 opt-in.
 *
 *  ★ owner/delegate 메인넷 = 타임락+멀티시그, 비업그레이더블.
 *  ★ DVN (가) 독립 2-Required 는 컨트랙트 밖(layerzero.config) — 운영 크리티컬.
 * ==========================================================================*/
contract MolePinOFT is OFT, RateLimiter {
    uint16 public bridgeFeeBps;
    uint16 public constant MAX_BRIDGE_FEE_BPS = 100; // hard cap 1% (대표 방침: 적게)
    address public feeCollector;

    address public guardian;
    bool    public bridgePaused;
    mapping(uint32 => bool) public pausedEid;
    mapping(address => bool) public blocked;
    bool public blocklistRenounced;

    event BridgeFeeSet(uint16 bps);
    event FeeCollectorSet(address indexed c);
    event GuardianSet(address indexed g);
    event BridgePaused(bool paused);
    event EidPaused(uint32 indexed eid, bool paused);
    event Blocked(address indexed a, bool b);
    event BlocklistRenounced();

    constructor(
        address _lzEndpoint, // 해당 체인 LayerZero EndpointV2
        address _owner       // delegate+owner == (메인넷)타임락+멀티시그
    ) OFT("MolePin", "MOL", _lzEndpoint, _owner) Ownable(_owner) {
        feeCollector = _owner; // 변경 가능. bridgeFeeBps 기본 0 → 수수료 경로 비활성
    }

    // ── blocklist (sender-only, bridge-safe) ──
    function setBlocked(address a, bool b) external onlyOwner {
        require(!blocklistRenounced, "MOL: renounced");
        blocked[a] = b; emit Blocked(a, b);
    }
    function renounceBlocklist() external onlyOwner { blocklistRenounced = true; emit BlocklistRenounced(); }

    function _update(address from, address to, uint256 value) internal virtual override {
        // ★ v2: sender 만 차단. from=0(mint/인바운드)·to=blocked 는 통과
        //   → 인바운드 절대 안 막힘(보존 유지). blocked 는 송금만 동결.
        require(!blocked[from], "MOL: sender blocked");
        super._update(from, to, value);
    }

    // ── fee 관리 ──
    function setBridgeFee(uint16 bps) external onlyOwner { require(bps <= MAX_BRIDGE_FEE_BPS, "MOL: fee high"); bridgeFeeBps = bps; emit BridgeFeeSet(bps); }
    function setFeeCollector(address c) external onlyOwner { require(c != address(0), "MOL: zero"); feeCollector = c; emit FeeCollectorSet(c); }

    // ── pause (비대칭: pause=guardian/owner, unpause=owner only) ──
    modifier onlyGuardianOrOwner() { require(msg.sender == guardian || msg.sender == owner(), "MOL: not guardian/owner"); _; }
    function setGuardian(address g) external onlyOwner { guardian = g; emit GuardianSet(g); }
    function pauseBridge() external onlyGuardianOrOwner { bridgePaused = true; emit BridgePaused(true); }
    function unpauseBridge() external onlyOwner { bridgePaused = false; emit BridgePaused(false); }
    function pauseEid(uint32 eid, bool p) external onlyGuardianOrOwner { pausedEid[eid] = p; emit EidPaused(eid, p); }
    function _requireBridgeActive(uint32 eid) internal view { require(!bridgePaused && !pausedEid[eid], "MOL: bridge paused"); }

    // ── RateLimiter 공개 설정 (onlyOwner) ──
    function setRateLimits(RateLimitConfig[] calldata cfgs) external onlyOwner { _setRateLimits(cfgs); }
    function resetRateLimits(uint32[] calldata eids) external onlyOwner { _resetRateLimits(eids); }

    /* ---- 아웃바운드: 보존-안전 수수료 + 크로싱분만 burn ---- */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _requireBridgeActive(_dstEid);

        uint256 sent = _removeDust(_amountLD);
        require(sent > 0, "MOL: zero after dust");

        uint256 fee = (sent * bridgeFeeBps) / 10_000;
        uint256 crossing = sent - fee;
        require(crossing >= _minAmountLD, "MOL: slippage");

        // opt-in 한도: 설정된 eid 만 enforce (미설정 = 무제한, brick 방지)
        if (rateLimits[_dstEid].limit > 0) _outflow(_dstEid, sent);

        // 수수료분: 소각 X — 이 체인 collector 로 이동(공급 불변, 재분배만)
        if (fee > 0) _transfer(_from, feeCollector, fee);
        // 크로싱분만 소각 → 도착 체인이 정확히 이만큼 mint → 보존 I2
        _burn(_from, crossing);

        amountSentLD = sent;          // 유저에게서 빠진 총량(crossing+fee)
        amountReceivedLD = crossing;  // 도착 mint 양
    }

    /* ---- quote 정합: _debitView 도 동일 산식 ---- */
    function _debitView(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 /*_dstEid*/
    ) internal view virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        uint256 sent = _removeDust(_amountLD);
        uint256 fee = (sent * bridgeFeeBps) / 10_000;
        uint256 crossing = sent - fee;
        require(crossing >= _minAmountLD, "MOL: slippage");
        amountSentLD = sent;
        amountReceivedLD = crossing;
    }

    /* ---- 인바운드: pause + RateLimiter inflow + mint ---- */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        _requireBridgeActive(_srcEid); // pause 시 revert → LZ 재시도(손실 X)
        _inflow(_srcEid, _amountLD);    // 미설정이어도 안전(0 감산)
        if (_to == address(0)) _to = address(0xdead);
        _mint(_to, _amountLD);
        return _amountLD;
    }

    /* ========================================================================
     *  AUDIT 체크리스트 (이 컨트랙트)
     *  [ ] ★최우선 _debit: 수수료분 비소각·collector 이동 / 크로싱분만 burn,
     *        amountReceivedLD==crossing → 이 체인 소각량==도착 mint량(보존 I2)
     *  [ ] _debitView 와 _debit 산식 일치(quote==실제)
     *  [ ] #5 blocklist sender-only: mint(from=0)·인바운드 안 막힘 검증
     *  [ ] pause: inbound revert 가 LZ v2 재시도로 안전 보류(손실 X)
     *  [ ] guardian 권한이 pause 한정(자금/설정 불가)
     *  [ ] RateLimiter opt-in 기본값 정책 결정(무제한 vs secure-by-default)
     *  [ ] 제네시스 0 / mint 는 _credit 경로로만 / 전 체인 합 ≤ 6.94T
     *  [ ] owner==타임락+멀티시그 / 비업그레이더블 / DVN (가) 설정(운영)
     * ======================================================================*/
}
