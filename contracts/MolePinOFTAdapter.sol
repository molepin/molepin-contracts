// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* ============================================================================
 *  MolePinOFTAdapter — CANONICAL LOCKBOX (BSC only)  · v2 audit-candidate
 * ----------------------------------------------------------------------------
 *  ⚠ 미감사. 외부 감사 + 테스트넷 재검증 전 메인넷 배포 금지.
 *  ★ mesh 전체에서 Adapter 는 단 1개(BSC).
 *
 *  [v2 변경]
 *   · #4 fix — _debit 를 pre/post 잔고 회계로:
 *       lock 전후 innerToken 잔고차(=실제 잠긴 양)만 크로스시킨다.
 *       MP 가 전송세를 물리든(어댑터 feeExempt 누락) 말든, "실제 잠긴 양 ==
 *       도착 체인 mint 양" 이 항상 성립 → 공급 드리프트 footgun 제거.
 *       feeExempt 는 이제 "정확성 요건"이 아니라 "UX 최적화"(있으면 유저가
 *       브릿지에서 전송세를 안 물어 1:1 깔끔). 없어도 안전(보존 유지),
 *       단 유저가 전송세만큼 적게 받음.
 *       ※ dust 제거 후 잔여(locked - removeDust)는 어댑터에 남아 "과담보"
 *         (locked ≥ minted, 절대 under 아님) — 안전 방향. 18/18 EVM 에선 0.
 *   · #1/#2 — Emergency Pause: 글로벌 + 경로별(eid). guardian 비대칭 권한
 *       (pause 는 guardian/owner, unpause 는 owner=타임락+멀티시그만).
 *       inbound pause 시 _credit revert → LZ v2 가 메시지 저장/재시도
 *       (손실 X, 의도된 임시 보류).
 *
 *  ★ owner/delegate 는 메인넷에서 타임락+멀티시그(Safe), 비업그레이더블.
 *  ★ DVN (가) 독립 2-Required 는 컨트랙트 밖 — LZ wiring(layerzero.config)
 *    으로 배포 시점 설정 (미적용 시 기본경로). 운영 보안 크리티컬.
 * ==========================================================================*/
contract MolePinOFTAdapter is OFTAdapter {
    using SafeERC20 for IERC20;

    // ── Emergency Pause (브릿지 경로 한정 — 일반 토큰 전송엔 영향 없음) ──
    address public guardian;                 // 빠른 pause 전용(좁은 권한)
    bool    public bridgePaused;             // 글로벌 브릿지 정지
    mapping(uint32 => bool) public pausedEid; // 경로별(eid) 정지

    event GuardianSet(address indexed g);
    event BridgePaused(bool paused);
    event EidPaused(uint32 indexed eid, bool paused);

    constructor(
        address _token,      // 배포된 MolePin(MOL)
        address _lzEndpoint, // BSC LayerZero EndpointV2
        address _owner       // delegate+owner == (메인넷)타임락+멀티시그
    ) OFTAdapter(_token, _lzEndpoint, _owner) Ownable(_owner) {}

    // ── pause 관리 (비대칭: 멈추긴 쉽게, 풀긴 어렵게) ──
    modifier onlyGuardianOrOwner() {
        require(msg.sender == guardian || msg.sender == owner(), "MOL: not guardian/owner");
        _;
    }
    function setGuardian(address g) external onlyOwner { guardian = g; emit GuardianSet(g); }
    function pauseBridge() external onlyGuardianOrOwner { bridgePaused = true; emit BridgePaused(true); }
    function unpauseBridge() external onlyOwner { bridgePaused = false; emit BridgePaused(false); } // owner only
    function pauseEid(uint32 eid, bool p) external onlyGuardianOrOwner { pausedEid[eid] = p; emit EidPaused(eid, p); }

    function _requireBridgeActive(uint32 eid) internal view {
        require(!bridgePaused && !pausedEid[eid], "MOL: bridge paused");
    }

    /* ---- 아웃바운드(LOCK): pre/post 잔고로 실제 잠긴 양 산출 ---- */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _requireBridgeActive(_dstEid);

        uint256 balBefore = innerToken.balanceOf(address(this));
        innerToken.safeTransferFrom(_from, address(this), _amountLD);
        uint256 locked = innerToken.balanceOf(address(this)) - balBefore; // 실제 잠긴 양

        locked = _removeDust(locked); // 체인 간 decimals 안전(18/18 EVM 에선 항등)
        require(locked > 0, "MOL: zero after dust");
        require(locked >= _minAmountLD, "MOL: slippage");

        // 도착 체인이 mint 할 양 == 실제 잠긴 양 → 보존 불변식 I2 항상 성립
        amountSentLD = locked;
        amountReceivedLD = locked;
    }

    /* ---- 인바운드(UNLOCK): base 동작 유지 + pause ---- */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        _requireBridgeActive(_srcEid); // pause 시 revert → LZ 재시도(손실 X)
        innerToken.safeTransfer(_to, _amountLD); // unlock (락잔고에서 방출)
        return _amountLD;
    }

    /* ========================================================================
     *  AUDIT 체크리스트 (이 컨트랙트)
     *  [ ] ★ _debit pre/post 회계: 실제 잠긴 양 == 도착 mint 양 정합 (최우선)
     *  [ ] dust 잔여가 어댑터에 남는 과담보 방향(절대 under-collateral 아님) 확인
     *  [ ] pause: inbound revert 가 LZ v2 재시도로 안전 보류되는지(손실 X)
     *  [ ] guardian 권한 범위가 pause 한정(자금/설정 불가)인지
     *  [ ] mesh Adapter 가 BSC 1개뿐 / owner==타임락+멀티시그 / 비업그레이더블
     *  [ ] DVN (가) 독립 2-Required 가 layerzero.config 로 설정됐는지(운영)
     * ======================================================================*/
}
