// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title MolePin (MOL)
 * @notice Home-chain (BSC) base token of the MolePin ecosystem. Intentionally kept "pure".
 *         (KO: MolePin 생태계의 기축 토큰. 의도적으로 순수하게 유지한다.)
 *
 * @dev Design principles (immutable):
 *  - Fixed supply: 6,942,420,888,888 MOL, fully minted at deployment. No mint function exists,
 *    so issuance can never increase. GENESIS_SUPPLY is the symbolic, permanent max supply;
 *    burning can only reduce it, never raise it.
 *  - Pure ERC20: transfers carry no fee/limit/blacklist/rebase, ensuring frictionless DEX
 *    listing (PancakeSwap/Uniswap) and Chainlink CCT pool compatibility.
 *  - All policy (cross-chain fee, discounts, staking, rewards, reputation) lives in separate
 *    L2 modules that merely reference this token as IERC20. None of it touches the token.
 *
 *  Included:
 *  - ERC20Permit (EIP-2612): gasless signature approvals (onboarding / gasless payments).
 *  - ERC20Burnable: holders may burn only their own balance (voluntary). No rebase/forced burn.
 *  - Ownable2Step: ownership transfers in two steps (anti-mistake/hijack). Move to multisig/timelock later.
 *
 *  Owner scope is intentionally minimal: the owner cannot touch supply, balances, or transfers
 *  (no such functions exist). Owner can only perform 2-step ownership transfer.
 *  (KO: owner는 공급/잔고/전송에 개입 불가 — 그런 함수가 없음. 소유권 이전만 가능.)
 */
contract MolePin is ERC20, ERC20Burnable, ERC20Permit, Ownable2Step {
    /// @notice Genesis (and permanent max) supply: 6,942,420,888,888 MOL at 18 decimals.
    /// (KO: 창세기 = 영원한 상한 발행량.)
    uint256 public constant GENESIS_SUPPLY = 6_942_420_888_888 * 1e18;

    /// @param initialOwner Receives ownership and the entire genesis supply at deployment.
    ///        Distribution/reserve funding is done afterwards via plain transfers.
    ///        (KO: 배포 시 소유권과 전량 토큰을 받는 주소. 이후 분배는 일반 transfer로.)
    constructor(address initialOwner)
        ERC20("MolePin", "MOL")
        ERC20Permit("MolePin")
        Ownable(initialOwner)
    {
        // Mint once. No other mint path exists anywhere -> 6.94T is the hard ceiling.
        _mint(initialOwner, GENESIS_SUPPLY);
    }

    // decimals() uses the ERC20 default of 18 (no override needed).
    //
    // Intentionally NOT included:
    //   - mint            : no further issuance (immutability)
    //   - transfer fee/limit : DEX & CCT friendly, purity preserved (fees live in the gateway)
    //   - blacklist/pause : decentralization, cartel-resistance
    //   - rebase/forced burn : holder balances are inviolable
}
