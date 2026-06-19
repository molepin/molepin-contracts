// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal interface required by Chainlink CCT BurnMintTokenPool.
/// @dev Declared inline because @chainlink/contracts pins OZ 4.8.3 (version clash with OZ 5.x).
///      Signatures match, so the CCT pool interacts with it correctly.
///      (KO: CCIP 풀이 요구하는 인터페이스. 버전 충돌 회피 위해 직접 선언.)
interface IBurnMintERC20 is IERC20 {
    function mint(address account, uint256 amount) external;
    function burn(uint256 amount) external;
    function burn(address account, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
}

/**
 * @title MolePinRemote (MOL)
 * @notice Remote-chain MOL token (every chain except the BSC home), used with a CCT BurnMintTokenPool.
 *         (KO: BSC가 아닌 리모트 체인용 MOL 토큰. CCT BurnMint 풀과 함께 사용.)
 *
 * @dev Why it differs from the home token (MolePin.sol):
 *  - Home (BSC): original 6.94T is minted and a LockRelease pool locks/releases it. No mint needed.
 *  - Remote: no original exists. When a user bridges BSC->here, the BurnMint pool mints that amount;
 *    bridging back burns it. So the pool must be able to mint/burn.
 *
 *  How immutability is preserved:
 *  - Starts at 0 supply (nothing minted in constructor).
 *  - mint/burn are restricted to MINTER_ROLE/BURNER_ROLE (= the CCT pool only). No human can mint freely.
 *  - Remote circulating supply is always 1:1 with the amount locked in the BSC LockRelease pool
 *    (enforced by CCT). Total ecosystem supply stays fixed at the BSC 6.94T; remote mints are not
 *    new issuance but a representation of BSC-locked tokens on another chain.
 *  (KO: 0에서 시작, 풀만 mint/burn. 총량은 BSC lock과 1:1 — 새 발행 아님, 불변 유지.)
 *
 *  Purity: like the home token, no transfer fee/blacklist/pause/rebase -> DEX & CCT compatible.
 */
contract MolePinRemote is ERC20, ERC20Burnable, ERC20Permit, Ownable2Step, AccessControl, IBurnMintERC20 {
    /// @notice Mint/burn roles granted exclusively to the CCT pool.
    /// (KO: CCT 풀에게만 부여되는 발행/소각 권한.)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @notice Symbolic max (same number as home). Actual circulating tracks BSC-locked amount 1:1.
    /// (KO: 참고용 상한 상징. 실제 유통은 BSC lock과 1:1.)
    uint256 public constant GENESIS_SUPPLY = 6_942_420_888_888 * 1e18;

    constructor(address initialOwner)
        ERC20("MolePin", "MOL")
        ERC20Permit("MolePin")
        Ownable(initialOwner)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        // No mint here. Remote starts at 0 -> pool mints only what is bridged in.
    }

    /// @notice Grant mint+burn roles to the CCT pool. Called by admin (owner) after deployment.
    /// (KO: 배포 후 owner가 CCT 풀 주소에 mint/burn 권한 부여.)
    function grantPoolRoles(address pool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, pool);
        _grantRole(BURNER_ROLE, pool);
    }

    /// @notice CCT-standard alias for grantPoolRoles. Grants MINTER+BURNER to the pool.
    /// @dev Signature matches Chainlink's BurnMintERC20.grantMintAndBurnRoles(address) so that
    ///      the standard ccip tooling (deployTokenPool task, etc.) works against this token as-is.
    ///      The explicit onlyRole(DEFAULT_ADMIN_ROLE) modifier makes the access intent self-evident
    ///      at the signature level; it is also redundantly enforced by the internal grantRole check.
    ///      (KO: ccip 표준 툴이 기대하는 시그니처 별칭. 명시적 admin 제한 + grantRole 내부 검사 이중 보호.)
    function grantMintAndBurnRoles(address burnAndMinter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, burnAndMinter);
        _grantRole(BURNER_ROLE, burnAndMinter);
    }

    /// @notice Atomically migrate DEFAULT_ADMIN_ROLE alongside ownership.
    /// @dev Ownable2Step calls _transferOwnership() only when the pending owner calls acceptOwnership().
    ///      Without this override, DEFAULT_ADMIN_ROLE would stay with the original deployer after a
    ///      2-step transfer, so the new owner could not call grantPoolRoles / grantMintAndBurnRoles —
    ///      role authority would diverge from ownership. We revoke the role from the outgoing owner and
    ///      grant it to the incoming owner in the same call. Guarded against no-op/self-transfer.
    ///      (KO: 소유권 수락 시점에 DEFAULT_ADMIN_ROLE도 함께 신규 owner로 원자적 이관. 권한-소유권 불일치 방지.)
    function _transferOwnership(address newOwner) internal override {
        address previousOwner = owner();
        super._transferOwnership(newOwner);
        if (newOwner != previousOwner) {
            if (previousOwner != address(0)) {
                _revokeRole(DEFAULT_ADMIN_ROLE, previousOwner);
            }
            if (newOwner != address(0)) {
                _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
            }
        }
    }

    // ── IBurnMintERC20 (called by the CCT pool) ──────────────────────────────
    function mint(address account, uint256 amount) external override onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function burn(uint256 amount) public override(ERC20Burnable, IBurnMintERC20) onlyRole(BURNER_ROLE) {
        _burn(msg.sender, amount);
    }

    /// @notice Burn from an arbitrary account. Restricted to BURNER_ROLE (= the CCT pool only).
    /// @dev NO _spendAllowance here, BY DESIGN — this matches Chainlink's standard BurnMintERC20.
    ///      In the CCT BurnMint flow the pool burns tokens it already custodies (moved to the pool by
    ///      the lock/burn step), so requiring an ERC20 allowance would break the pool. Safety rests on
    ///      BURNER_ROLE being granted EXCLUSIVELY to the CCT pool (never an EOA or third party). For
    ///      allowance-gated burns, use burnFrom() instead.
    ///      (KO: CCT 표준과 동일하게 의도적으로 allowance 미검사. BURNER_ROLE은 CCT 풀 전용. 권한 외 부여 금지.)
    function burn(address account, uint256 amount) external override onlyRole(BURNER_ROLE) {
        _burn(account, amount);
    }

    function burnFrom(address account, uint256 amount)
        public
        override(ERC20Burnable, IBurnMintERC20)
        onlyRole(BURNER_ROLE)
    {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    // ── Interface support ────────────────────────────────────────────────────
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return interfaceId == type(IBurnMintERC20).interfaceId
            || interfaceId == type(IERC20).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
