// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/* ============================================================================
 *  MolePin (MOL) — CANONICAL TOKEN (BSC only)  · v2 audit-candidate
 * ----------------------------------------------------------------------------
 *  WARNING: Unaudited. "Mainnet candidate (audit input)" — do NOT deploy to
 *  mainnet before an external audit + testnet re-verification.
 *  (KO: 미감사. 외부 감사 + 테스트넷 재검증 전 메인넷 배포 금지.)
 *
 *  [v2 changes]
 *   - Blocklist is now sender-only (from), previously (from && to).
 *     Reason (#5 fix): blocking `to` would revert adapter unlock (adapter->user)
 *     and inbound paths -> stuck cross-chain messages + conservation violation.
 *     Now a blocked address "cannot send" (funds frozen) but "can still receive"
 *     -> inbound/unlock is never blocked. Sending after receipt is blocked
 *     (freeze goal still achieved).
 *     (KO: 블록리스트를 sender(from) 한정으로 변경. blocked는 송금 동결,
 *      수신은 가능 -> unlock/인바운드 절대 안 막힘.)
 *   - ★ Governance must NEVER block the Adapter address: blocking from=adapter
 *     would stop unlock -> bridge halts. (sender-only removes general stuck risk;
 *     this is the one operational rule — consider an on-chain guard at audit.)
 *     (KO: 거버넌스는 Adapter 주소를 절대 block 금지. unlock 막히면 브릿지 정지.)
 *
 *  Invariant I1: minted once in the constructor, no mint path ever exists
 *  afterward -> totalSupply ≡ 6.94T. (KO: 1회 발행 후 mint 경로 영구 부재.)
 *  ★ Adapter feeExempt is demoted to a "recommended optimization" (Adapter v2
 *    guarantees correctness via pre/post balance accounting -> no supply drift
 *    even if forgotten; feeExempt only makes the UX clean by sparing the user
 *    the transfer fee on bridging).
 *    (KO: feeExempt는 정확성 요건이 아니라 UX 최적화로 강등. 없어도 보존 안전.)
 * ==========================================================================*/
contract MolePin {
    string public constant name = "MolePin";
    string public constant symbol = "MOL";
    uint8  public constant decimals = 18;
    uint256 public constant GLOBAL_MAX_SUPPLY = 6_942_420_888_888 * 1e18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public governance;
    address public pendingGovernance;
    uint16  public transferFeeBps;
    uint16  public constant MAX_TRANSFER_FEE_BPS = 200;
    address public feeCollector;
    mapping(address => bool) public feeExempt;
    mapping(address => bool) public blocked;
    bool public blocklistRenounced;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event GovernanceTransferStarted(address indexed prev, address indexed next);
    event GovernanceTransferred(address indexed prev, address indexed next);
    event FeeExemptSet(address indexed a, bool e);
    event TransferFeeSet(uint16 bps);
    event FeeCollectorSet(address indexed c);
    event Blocked(address indexed a, bool b);
    event BlocklistRenounced();

    modifier onlyGov() { require(msg.sender == governance, "MOL: not gov"); _; }

    constructor(address treasury_, address governance_, address feeCollector_) {
        require(treasury_ != address(0) && governance_ != address(0) && feeCollector_ != address(0), "MOL: zero");
        governance = governance_;
        feeCollector = feeCollector_;
        totalSupply = GLOBAL_MAX_SUPPLY;
        balanceOf[treasury_] = GLOBAL_MAX_SUPPLY;
        emit Transfer(address(0), treasury_, GLOBAL_MAX_SUPPLY);
        feeExempt[treasury_] = true;
        feeExempt[feeCollector_] = true;
        emit FeeExemptSet(treasury_, true);
        emit FeeExemptSet(feeCollector_, true);
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v; emit Approval(msg.sender, s, v); return true;
    }
    function transfer(address to, uint256 v) external returns (bool) { _transfer(msg.sender, to, v); return true; }
    function transferFrom(address f, address to, uint256 v) external returns (bool) {
        uint256 a = allowance[f][msg.sender];
        require(a >= v, "MOL: allowance");
        if (a != type(uint256).max) allowance[f][msg.sender] = a - v;
        _transfer(f, to, v); return true;
    }

    function _transfer(address f, address t, uint256 v) internal {
        require(t != address(0), "MOL: zero to");
        // v2: block sender only (bridge-safe). blocked = cannot send (frozen),
        // can still receive -> adapter unlock / inbound never blocked.
        // (KO: sender만 차단. blocked는 송금 동결, 수신 가능.)
        require(!blocked[f], "MOL: sender blocked");
        require(balanceOf[f] >= v, "MOL: balance");
        uint256 fee = 0;
        if (transferFeeBps != 0 && !feeExempt[f] && !feeExempt[t]) fee = (v * transferFeeBps) / 10_000;
        unchecked { balanceOf[f] -= v; balanceOf[t] += v - fee; if (fee != 0) balanceOf[feeCollector] += fee; }
        emit Transfer(f, t, v - fee);
        if (fee != 0) emit Transfer(f, feeCollector, fee);
    }

    function setTransferFee(uint16 bps) external onlyGov { require(bps <= MAX_TRANSFER_FEE_BPS, "MOL: fee high"); transferFeeBps = bps; emit TransferFeeSet(bps); }
    function setFeeCollector(address c) external onlyGov { require(c != address(0), "MOL: zero"); feeCollector = c; feeExempt[c] = true; emit FeeCollectorSet(c); emit FeeExemptSet(c, true); }
    function setFeeExempt(address a, bool e) external onlyGov { feeExempt[a] = e; emit FeeExemptSet(a, e); }
    function setBlocked(address a, bool b) external onlyGov { require(!blocklistRenounced, "MOL: renounced"); blocked[a] = b; emit Blocked(a, b); }
    function renounceBlocklist() external onlyGov { blocklistRenounced = true; emit BlocklistRenounced(); }
    function transferGovernance(address n) external onlyGov { pendingGovernance = n; emit GovernanceTransferStarted(governance, n); }
    function acceptGovernance() external { require(msg.sender == pendingGovernance, "MOL: not pending"); emit GovernanceTransferred(governance, pendingGovernance); governance = pendingGovernance; pendingGovernance = address(0); }
}
