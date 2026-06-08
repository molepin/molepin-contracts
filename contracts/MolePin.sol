// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/* ============================================================================
 *  MolePin (MOL) — CANONICAL TOKEN (BSC only)  · v2 audit-candidate
 * ----------------------------------------------------------------------------
 *  ⚠ 미감사. "메인넷 후보(감사 입력)" — 외부 감사 + 테스트넷 재검증 전
 *    메인넷 배포 금지.
 *
 *  [v2 변경]
 *   · 블록리스트를 sender(from) 한정으로 변경 (이전: from && to).
 *     이유(#5 결함 수정): to 까지 막으면 Adapter unlock(adapter→유저)이나
 *     인바운드 경로가 revert → 크로스체인 메시지 stuck + 보존 불변식 위반.
 *     이제 blocked 주소는 "보낼 수 없음"(자금 동결)이나 "받을 수는 있음"
 *     → 인바운드/unlock 절대 안 막힘. 받은 뒤 전송은 막힘(동결 목적 달성).
 *   · ★ 거버넌스는 Adapter 주소를 절대 block 하지 말 것: from=adapter 인
 *     unlock 이 막히면 브릿지 정지. (sender-only 라 일반 stuck 위험은 제거,
 *     이 한 가지만 운영 규칙 — 감사 시 온체인 가드 추가 검토)
 *
 *  불변식 I1: 생성자 1회 발행 후 mint 경로 영구 부재 → totalSupply ≡ 6.94T.
 *  ★ Adapter feeExempt 는 "권장 최적화"로 강등 (Adapter v2 가 pre/post 잔고
 *    회계로 정확성 보장 → 잊어도 공급 드리프트 없음. feeExempt 시 유저가
 *    브릿지에서 전송세를 안 물어 UX 만 깔끔).
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
        // ★ v2: sender 만 차단 (bridge-safe). blocked = 보낼 수 없음(동결),
        //   받을 수는 있음 → Adapter unlock/인바운드 절대 안 막힘.
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
