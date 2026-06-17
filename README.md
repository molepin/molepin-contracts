# MolePin (MOL)

**A fixed-supply omnichain MemeFi token, live across 7 EVM chains via Chainlink CCIP / Cross-Chain Token (CCT).**

MolePin keeps one invariant above everything: the total supply of MOL across every chain always equals the genesis supply of **6,942,420,888,888 MOL**. Bridging never creates or destroys MOL — it moves it.

> **KO:** MolePin(MOL)은 고정 공급 옴니체인 MemeFi 토큰입니다. 7개 EVM 체인에서 Chainlink CCIP/CCT로 작동하며, 모든 체인의 MOL 총합은 항상 창세기 공급량 **6,942,420,888,888 MOL**과 같습니다. 브리지는 MOL을 새로 만들거나 없애지 않고 이동시킬 뿐입니다.

---

## Design principles

- **Supply invariance** — Total MOL across all chains always equals the genesis supply. The BSC home chain locks/releases the original supply; remote chains mint/burn a 1:1 representation. Enforced by Chainlink CCT.
- **Token-pure / policy-in-gateway** — The MOL token contracts carry no bridge logic, fees, limits, blacklist, or pause. All cross-chain policy lives in a separate gateway contract. This keeps the token frictionless for DEX listing and CCT pools.
- **Native fee collection** — Bridge fees are collected in the source chain's native gas token (BNB, ETH, POL, AVAX…), not in MOL.
- **Owner → multisig trajectory** — A single owner key today, with a Safe multisig / timelock as the target.

> **KO:** 공급 불변(모든 체인 총합 = 창세기 공급), 토큰 순수성(브리지 로직은 게이트웨이에만), 네이티브 수수료(출발 체인 가스 토큰으로 징수), owner→멀티시그 지향.

---

## Architecture at a glance

```
        ┌──────────────────────── BSC (home) ────────────────────────┐
        │  MolePin (ERC20, fixed 6.94T)                               │
        │  LockRelease Pool  ←──lock/release──→  Gateway              │
        └──────────────────────────────┬─────────────────────────────┘
                                        │ Chainlink CCIP
        ┌───────────────────────────────┼───────────────────────────────┐
        │                               │                               │
   ┌────▼─────┐   ┌────────┐   ┌────────▼─┐   ┌────────┐   ┌──────────┐   ┌─────────┐
   │ Ethereum │   │Polygon │   │ Arbitrum │   │Optimism│   │   Base   │   │Avalanche│
   │ MolePinRemote + BurnMint Pool + Gateway  (mint on arrival / burn on send)      │
   └──────────┴───┴────────┴───┴──────────┴───┴────────┴───┴──────────┴───┴─────────┘
```

- **Home (BSC):** the full 6.94T supply exists here. A **LockRelease** pool locks MOL on outbound bridges and releases it on inbound.
- **Remote (6 chains):** `MolePinRemote` starts at 0 supply. A **BurnMint** pool mints MOL when it arrives and burns it when it leaves. Circulating remote supply tracks the BSC-locked amount 1:1.
- **Gateway (all 7 chains):** wraps CCT to collect a native fee, enforce trusted routes, and forward minted tokens to the end user. Same address on every chain (CREATE2).

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full transfer lifecycle.

> **KO:** 홈(BSC)은 전량 6.94T 보유 + LockRelease 풀. 리모트 6체인은 0에서 시작 + BurnMint 풀(도착 시 mint, 출발 시 burn). 게이트웨이는 7체인 모두 동일 주소(CREATE2)로 네이티브 수수료·신뢰 경로·forward를 담당.

---

## Deployed contracts (mainnet)

All gateways share one address; all 6 remote tokens share one address (CREATE2 + identical token address ⇒ identical pool/gateway addresses).

| Contract | Address |
|---|---|
| **Gateway** (all 7 chains) | `0x6942cb929de1e5747A3Ed72c7bD698f2aEdD3a55` |
| **MolePin** (home token, BSC) | `0x6942E2bb91b1C0Efaae67f03DBAB611107fBBd80` |
| **MolePinRemote** (6 remote chains) | `0x6942c0fD0d4655Ba8ee1251E204103AADb6Fee20` |
| **LockRelease pool** (BSC) | `0x36aa3d0700e7bf8a91b9353ab51423abb628b581` |
| **BurnMint pool** (6 remote chains) | `0xee89111388f3bead196f36f95ed997269ed0bab6` |

Per-chain selectors and the full matrix are in [`docs/DEPLOYMENTS.md`](docs/DEPLOYMENTS.md).

> **KO:** 게이트웨이는 7체인 동일 주소, 리모트 토큰은 6체인 동일 주소(CREATE2 + 동일 토큰 주소 → 동일 풀/게이트웨이 주소). 체인별 selector는 DEPLOYMENTS.md 참조.

---

## Repository layout

```
contracts/
  MolePin.sol              # Home token (BSC) — pure fixed-supply ERC20
  MolePinRemote.sol        # Remote token — BurnMint (MINTER/BURNER = CCT pool)
  MolePinBridgeGateway.sol # Native-fee gateway over CCT
test/                      # Hardhat 3 (mocha/chai + viem) tests
docs/
  ARCHITECTURE.md          # Transfer lifecycle, gateway design, supply model
  TOKENOMICS.md            # Supply, fees, distribution model
  DEPLOYMENTS.md           # Per-chain addresses & selectors
```

> **Note:** deployment scripts, operational tooling, and internal runbooks are intentionally **not** included in this public repository. This repo contains contracts, tests, and documentation only.
>
> **KO:** 배포 스크립트·운영 도구·내부 런북은 공개 레포에 의도적으로 포함하지 않습니다. 이 레포는 컨트랙트·테스트·문서만 담습니다.

---

## Tech stack

- **Solidity** 0.8.28 (EVM Cancun), OpenZeppelin 5.x
- **Hardhat 3** + Ignition + viem
- **Chainlink CCIP / CCT** — LockRelease (home) + BurnMint (remote)
- **CREATE2** for identical cross-chain addresses

---

## Security

- The token contracts have **no mint path** beyond genesis (home) or the CCT pool (remote), **no transfer fee/limit**, **no blacklist**, and **no pause** — owner cannot touch supply, balances, or transfers.
- Remote mint/burn is restricted to `MINTER_ROLE` / `BURNER_ROLE`, held only by the CCT pool.
- Ownership uses `Ownable2Step`; migration to a Safe multisig / timelock is on the roadmap.
- Responsible disclosure: please open a security advisory rather than a public issue.

> **KO:** 토큰은 창세기(홈)/풀(리모트) 외 발행 경로 없음, 전송세·한도·블랙리스트·pause 없음. 리모트 발행/소각은 CCT 풀(MINTER/BURNER)만 가능. 소유권은 2단계, 멀티시그 이전 예정.

---

## License

MIT. See [`LICENSE`](LICENSE).
