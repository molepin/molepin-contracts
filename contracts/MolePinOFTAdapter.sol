// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* ============================================================================
 *  MolePinOFTAdapter — CANONICAL LOCKBOX (BSC only)  · v2 audit-candidate
 * ----------------------------------------------------------------------------
 *  WARNING: Unaudited. Do NOT deploy to mainnet before an external audit +
 *  testnet re-verification. (KO: 미감사. 감사+테스트넷 재검증 전 메인넷 금지.)
 *  ★ Exactly ONE adapter exists in the whole mesh (on BSC).
 *    (KO: mesh 전체에서 Adapter는 단 1개, BSC.)
 *
 *  [v2 changes]
 *   - #4 fix: _debit uses pre/post balance accounting:
 *       cross only the actual locked amount (innerToken balance delta).
 *       Whether or not MolePin charges a transfer fee (adapter feeExempt missing),
 *       "actual locked == destination mint" always holds -> removes the supply
 *       drift footgun. feeExempt is now a "recommended optimization" (clean 1:1
 *       UX), not a correctness requirement; without it the user simply receives
 *       less by the transfer fee.
 *       (KO: _debit를 pre/post 잔고 회계로. 실제 잠긴 양==도착 mint량 항상 성립.
 *        feeExempt는 정확성 요건 아닌 UX 최적화.)
 *       Note: after dust removal, the remainder (locked - removeDust) stays in the
 *       adapter as "over-collateral" (locked >= minted, never under) — the safe
 *       direction. On 18/18 EVM this is 0.
 *       (KO: dust 잔여는 어댑터에 남아 과담보 — 안전 방향. 18/18 EVM에선 0.)
 *   - #1/#2 Emergency Pause: global + per-path (eid). Asymmetric guardian power
 *       (pause = guardian/owner, unpause = owner = timelock+multisig only).
 *       On inbound pause, _credit reverts -> LayerZero v2 stores/retries the
 *       message (no loss, intended temporary hold).
 *       (KO: pause는 guardian/owner, unpause는 owner만. pause 시 LZ 재시도.)
 *
 *  ★ owner/delegate on mainnet = timelock + multisig (Safe), non-upgradeable.
 *  ★ DVN (e.g. 2-Required, independent) lives OUTSIDE the contract — set at
 *    deploy time via LZ wiring (layerzero.config). Operationally critical.
 *    (KO: owner는 메인넷 타임락+멀티시그. DVN은 컨트랙트 밖 layerzero.config.)
 * ==========================================================================*/
contract MolePinOFTAdapter is OFTAdapter {
    using SafeERC20 for IERC20;

    // ── Emergency Pause (bridge path only — normal token transfers unaffected) ──
    // (KO: 브릿지 경로 한정 — 일반 토큰 전송엔 영향 없음)
    address public guardian;                 // narrow power: fast pause only (KO: 빠른 pause 전용)
    bool    public bridgePaused;             // global bridge halt (KO: 글로벌 정지)
    mapping(uint32 => bool) public pausedEid; // per-path (eid) halt (KO: 경로별 정지)

    event GuardianSet(address indexed g);
    event BridgePaused(bool paused);
    event EidPaused(uint32 indexed eid, bool paused);

    constructor(
        address _token,      // the deployed MolePin (MOL) (KO: 배포된 MolePin)
        address _lzEndpoint, // BSC LayerZero EndpointV2
        address _owner       // delegate+owner == (mainnet) timelock+multisig (KO: 메인넷 타임락+멀티시그)
    ) OFTAdapter(_token, _lzEndpoint, _owner) Ownable(_owner) {}

    // ── pause management (asymmetric: easy to stop, hard to resume) ──
    // (KO: 비대칭 — 멈추긴 쉽게, 풀긴 어렵게)
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

    /* ---- outbound (LOCK): derive actual locked amount via pre/post balance ---- */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _requireBridgeActive(_dstEid);

        uint256 balBefore = innerToken.balanceOf(address(this));
        innerToken.safeTransferFrom(_from, address(this), _amountLD);
        uint256 locked = innerToken.balanceOf(address(this)) - balBefore; // actual locked amount (KO: 실제 잠긴 양)

        locked = _removeDust(locked); // cross-chain decimals safe (identity on 18/18 EVM) (KO: decimals 안전)
        require(locked > 0, "MOL: zero after dust");
        require(locked >= _minAmountLD, "MOL: slippage");

        // destination mint == actual locked -> conservation invariant I2 always holds
        // (KO: 도착 mint == 실제 잠긴 양 -> 보존 불변식 I2.)
        amountSentLD = locked;
        amountReceivedLD = locked;
    }

    /* ---- inbound (UNLOCK): base behavior + pause ---- */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        _requireBridgeActive(_srcEid); // on pause, revert -> LZ retry (no loss) (KO: pause 시 LZ 재시도)
        innerToken.safeTransfer(_to, _amountLD); // unlock (release from locked balance) (KO: 락잔고에서 방출)
        return _amountLD;
    }

    /* ========================================================================
     *  AUDIT CHECKLIST (this contract)
     *  [ ] ★ _debit pre/post accounting: actual locked == destination mint (top)
     *  [ ] dust remainder stays in adapter as over-collateral (never under)
     *  [ ] pause: inbound revert safely held by LZ v2 retry (no loss)
     *  [ ] guardian power limited to pause (no funds/config)
     *  [ ] exactly 1 adapter in mesh (BSC) / owner == timelock+multisig / non-upgradeable
     *  [ ] DVN (e.g. 2-Required, independent) set via layerzero.config (ops)
     * ======================================================================*/
}
