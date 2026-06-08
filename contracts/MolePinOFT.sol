// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import { RateLimiter } from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/* ============================================================================
 *  MolePinOFT — REMOTE MINT/BURN TOKEN (all chains except BSC)  · v2 audit-candidate
 * ----------------------------------------------------------------------------
 *  WARNING: Unaudited. Do NOT deploy to mainnet before an external audit +
 *  testnet re-verification. (KO: 미감사. 감사+테스트넷 재검증 전 메인넷 금지.)
 *
 *  Genesis supply is 0 (no mint in constructor). Supply only increases via
 *  inbound bridge mint and only decreases via outbound burn, so the sum across
 *  all chains stays <= GLOBAL_MAX_SUPPLY.
 *  (KO: 제네시스 0. 인바운드 mint로만 증가, 아웃바운드 burn으로만 감소.)
 *
 *  [v2 changes]
 *   - #5 fix: blocklist in _update is sender-only (from), previously (from && to).
 *       mint (from=0) and inbound are never blocked -> no stuck messages /
 *       conservation violation. blocked = cannot send (frozen), can still receive.
 *       (KO: blocklist를 sender 한정으로. mint/인바운드 안 막힘.)
 *   - #1/#2 Emergency Pause: global + per-path (eid), asymmetric guardian power.
 *       On inbound pause, _credit reverts -> LayerZero v2 stores/retries the
 *       message (no loss). (KO: pause 시 _credit revert -> LZ 재시도, 손실 X.)
 *   - ★ Conservation-safe bridge fee (top audit priority, kept/strengthened from
 *       v1): the fee portion is NOT burned but moved to this chain's collector
 *       (supply unchanged, redistribution only). Only the crossing portion is
 *       _burn'd -> the destination mints exactly that much.
 *       Thus burned-here == minted-there (conservation I2). _debitView uses the
 *       same formula. (KO: 수수료분은 소각 X collector 이동, 크로싱분만 burn ->
 *       소각량==도착 mint량.)
 *   - RateLimiter: opt-in. Unconfigured eids are NOT enforced (prevents bridge
 *       brick — "halt all sends if unset" is an operational footgun). Only
 *       configured paths are rate-limited.
 *       (KO: RateLimiter opt-in. 미설정 eid는 무제한 — brick 방지.)
 *       Audit note: whether the default should be "unlimited (opt-in)" vs
 *       "forbidden until configured (secure-by-default)" is for audit+ops to
 *       finalize. Currently opt-in.
 *
 *  ★ owner/delegate on mainnet = timelock + multisig, non-upgradeable.
 *  ★ DVN (e.g. 2-Required, independent) lives OUTSIDE the contract
 *    (layerzero.config) — operationally critical.
 *    (KO: owner는 메인넷에서 타임락+멀티시그. DVN은 컨트랙트 밖 layerzero.config.)
 * ==========================================================================*/
contract MolePinOFT is OFT, RateLimiter {
    uint16 public bridgeFeeBps;
    uint16 public constant MAX_BRIDGE_FEE_BPS = 100; // hard cap 1% (policy: keep it low) (KO: 상한 1%)
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
        address _lzEndpoint, // LayerZero EndpointV2 on this chain (KO: 해당 체인 EndpointV2)
        address _owner       // delegate+owner == (mainnet) timelock+multisig (KO: 메인넷 타임락+멀티시그)
    ) OFT("MolePin", "MOL", _lzEndpoint, _owner) Ownable(_owner) {
        feeCollector = _owner; // changeable. bridgeFeeBps defaults to 0 -> fee path inactive
                               // (KO: 변경 가능. bridgeFeeBps 기본 0 -> 수수료 경로 비활성)
    }

    // ── blocklist (sender-only, bridge-safe) ──
    function setBlocked(address a, bool b) external onlyOwner {
        require(!blocklistRenounced, "MOL: renounced");
        blocked[a] = b; emit Blocked(a, b);
    }
    function renounceBlocklist() external onlyOwner { blocklistRenounced = true; emit BlocklistRenounced(); }

    function _update(address from, address to, uint256 value) internal virtual override {
        // v2: block sender only. from=0 (mint/inbound) and to=blocked pass through
        // -> inbound never blocked (conservation preserved). blocked freezes sends only.
        // (KO: sender만 차단. mint/인바운드 통과 -> 보존 유지.)
        require(!blocked[from], "MOL: sender blocked");
        super._update(from, to, value);
    }

    // ── fee management ──
    function setBridgeFee(uint16 bps) external onlyOwner { require(bps <= MAX_BRIDGE_FEE_BPS, "MOL: fee high"); bridgeFeeBps = bps; emit BridgeFeeSet(bps); }
    function setFeeCollector(address c) external onlyOwner { require(c != address(0), "MOL: zero"); feeCollector = c; emit FeeCollectorSet(c); }

    // ── pause (asymmetric: pause=guardian/owner, unpause=owner only) ──
    modifier onlyGuardianOrOwner() { require(msg.sender == guardian || msg.sender == owner(), "MOL: not guardian/owner"); _; }
    function setGuardian(address g) external onlyOwner { guardian = g; emit GuardianSet(g); }
    function pauseBridge() external onlyGuardianOrOwner { bridgePaused = true; emit BridgePaused(true); }
    function unpauseBridge() external onlyOwner { bridgePaused = false; emit BridgePaused(false); }
    function pauseEid(uint32 eid, bool p) external onlyGuardianOrOwner { pausedEid[eid] = p; emit EidPaused(eid, p); }
    function _requireBridgeActive(uint32 eid) internal view { require(!bridgePaused && !pausedEid[eid], "MOL: bridge paused"); }

    // ── RateLimiter public setters (onlyOwner) ──
    function setRateLimits(RateLimitConfig[] calldata cfgs) external onlyOwner { _setRateLimits(cfgs); }
    function resetRateLimits(uint32[] calldata eids) external onlyOwner { _resetRateLimits(eids); }

    /* ---- outbound: conservation-safe fee + burn the crossing portion only ---- */
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

        // opt-in limit: only enforce configured eids (unset = unlimited, brick-proof)
        // (KO: opt-in 한도. 설정된 eid만 enforce, 미설정=무제한.)
        if (rateLimits[_dstEid].limit > 0) _outflow(_dstEid, sent);

        // fee portion: NOT burned — moved to this chain's collector (supply unchanged)
        // (KO: 수수료분 소각 X, collector 이동 -> 공급 불변.)
        if (fee > 0) _transfer(_from, feeCollector, fee);
        // crossing portion only is burned -> destination mints exactly this -> I2
        // (KO: 크로싱분만 소각 -> 도착이 정확히 그만큼 mint -> 보존 I2.)
        _burn(_from, crossing);

        amountSentLD = sent;          // total debited from user (crossing + fee)
        amountReceivedLD = crossing;  // amount minted at destination
    }

    /* ---- quote consistency: _debitView uses the same formula ---- */
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

    /* ---- inbound: pause + RateLimiter inflow + mint ---- */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        _requireBridgeActive(_srcEid); // on pause, revert -> LZ retry (no loss) (KO: pause 시 revert -> LZ 재시도)
        _inflow(_srcEid, _amountLD);    // safe even if unset (subtracts 0) (KO: 미설정이어도 안전)
        if (_to == address(0)) _to = address(0xdead);
        _mint(_to, _amountLD);
        return _amountLD;
    }

    /* ========================================================================
     *  AUDIT CHECKLIST (this contract)
     *  [ ] ★ top: _debit fee not burned / moved to collector, crossing-only burn,
     *        amountReceivedLD == crossing -> burned-here == minted-there (I2)
     *  [ ] _debitView matches _debit (quote == actual)
     *  [ ] #5 blocklist sender-only: mint (from=0) / inbound not blocked
     *  [ ] pause: inbound revert safely held by LZ v2 retry (no loss)
     *  [ ] guardian power limited to pause (no funds/config)
     *  [ ] RateLimiter opt-in default policy (unlimited vs secure-by-default)
     *  [ ] genesis 0 / mint only via _credit / sum across chains <= 6.94T
     *  [ ] owner == timelock+multisig / non-upgradeable / DVN configured (ops)
     * ======================================================================*/
}
