# MolePin Contracts

Cross-chain MemeFi token built on **LayerZero v2 (OFT standard)**, with a native-fee
bridge gateway. Home chain holds a fixed-supply canonical token; remote chains mint/burn
mirrors. Supply is invariant across the whole mesh.

크로스체인 MemeFi 토큰. LayerZero v2 OFT 기반, native 수수료 게이트웨이.
홈체인은 고정공급 기축 토큰, 리모트 체인은 mint/burn 미러. 전 체인 공급 불변.

> ⚠️ **Unaudited.** Do not deploy to mainnet before an external audit.
> 미감사. 외부 감사 전 메인넷 배포 금지.

---

## Architecture

```
        BSC (home)                          Remote chains (Polygon, ...)
  ┌──────────────────┐                    ┌──────────────────┐
  │ MolePin (MOL)    │  fixed 6.94T       │ MolePinOFT       │  mint/burn, 0-genesis
  │ MolePinOFTAdapter│  lock / unlock     │ (LayerZero OFT)  │
  └────────┬─────────┘                    └────────┬─────────┘
           │                                       │
  ┌────────┴─────────┐                    ┌────────┴─────────┐
  │ BridgeGatewayLZ  │  native fee        │ BridgeGatewayLZ  │  native fee
  │ (USD_FIXED $1)   │  send wrapper      │ (LZ_MULTIPLE 2x) │  send wrapper
  └──────────────────┘                    └──────────────────┘
```

- **Home (BSC):** `MolePin` — fixed supply, no mint path, pure ERC20.
  `MolePinOFTAdapter` locks/unlocks it (LockRelease).
- **Remote:** `MolePinOFT` — mint on inbound, burn on outbound (BurnMint), 0-supply genesis.
- **Gateway (every chain):** wraps `OFT.send()` to collect a **native-token** business fee
  in the SAME transaction as the LayerZero send. Token stays pure; all fee policy lives in
  the gateway. (토큰은 순수, 정책은 게이트웨이에.)

### Why LayerZero OFT
- Token transfers are live on the target chains today (including TON).
- Native-fee is the protocol default; supply invariance via OFT burn/mint.
- Sender authenticity enforced by the OFT `peers` mapping (LayerZero standard).

---

## Contracts

| Contract | Role |
|---|---|
| `MolePin.sol` | Home-chain canonical token (BSC). Fixed supply, pure ERC20. |
| `MolePinOFTAdapter.sol` | Home lockbox. Locks MolePin to back remote mints. |
| `MolePinOFT.sol` | Remote mint/burn token. 0-supply genesis. |
| `MolePinBridgeGatewayLZ.sol` | Send-side gateway. Native fee + `OFT.send()` in one tx. |
| `MolePinLzOptions.sol` | On-chain LayerZero v2 execution-options encoder. |

### Fee model
- **USD_FIXED** (home): oracle-priced fixed USD fee (default $1, capped $5).
- **LZ_MULTIPLE** (remote): `molepinFee = lzFee * multiplier` (default 2x, capped 5x).
- Per-chain mode injected post-deploy via `configure()`; the 2-arg constructor keeps the
  gateway address deterministic for same-address (CREATE2) deployments.

---

## Build & Test

```bash
npm install
npx hardhat compile
npx hardhat test
```

Test coverage (39 cases):
- Gateway: configure (both modes), fee math (USD_FIXED & LZ_MULTIPLE), `bridge()`
  atomicity (native fee → treasury, lzFee → OFT, refund, no residue), owner controls.
- LZ options: 3-way byte parity between the JS builder, the on-chain Solidity library,
  and the official `@layerzerolabs/lz-v2-utilities` encoder.

Requires (dev): `@nomicfoundation/hardhat-chai-matchers`, `@layerzerolabs/lz-v2-utilities`.

---

## Design principles

- **Token purity:** transfers carry no bridge logic; fees & policy live in the gateway.
- **Supply invariance:** home lock amount == sum of remote mints, always.
- **Trust model:** LayerZero v2 DVN stack; production deployments use ≥2 independent
  required DVNs (configured outside the contracts).
- **Upgradeability:** none. Contracts are immutable; ownership moves to timelock+multisig.

---

## License
MIT
