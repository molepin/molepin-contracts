# MolePin Deploy Notes (BSC home + multichain)

## Contracts (compiled & verified, 2026-06-06)
| Contract | Role | Chain | Status |
|---|---|---|---|
| MolePin.sol | Home token (pure, immutable, 6.94T) | BSC | ✅ compiled |
| MolePinRemote.sol | Remote token (pool mint/burn) | Polygon/Base/etc | ✅ compiled |
| MolePinBridgeGateway.sol | Cross-chain transfer + fee | every EVM chain | ✅ compiled |
| mocks/MockPriceOracle.sol | Test AggregatorV3 | local | ✅ compiled |
| mocks/MockCCIPRouter.sol | Test CCIP router | local | ✅ compiled |

## ⚠ Compiler settings (required)
Solidity **0.8.28 + viaIR + evmVersion "cancun"** (matches the rest of the stack).
OpenZeppelin 5.x uses `mcopy` (Cancun opcode) — without "cancun" the build fails.
All target chains (BSC/Polygon/Base/Arbitrum/Optimism) support Cancun.

## CCT architecture (Option A)
- **BSC (home)**: MolePin 6.94T minted + LockReleaseTokenPool (CCT standard).
- **Remote**: MolePinRemote (starts at 0, pool mint/burn) + BurnMintTokenPool (CCT standard).
- Total supply fixed at BSC 6.94T; remote mint = 1:1 with BSC-locked amount (not new issuance).

## Fee policy (final)
- Every cross-chain transfer is charged, on every chain.
- Fee = source chain's native gas token worth **$1** (owner-adjustable, hard cap **$5** / immutable).
- Paid to treasury (deployer wallet, owner-changeable). MOL itself untouched.
- CCIP's own fee (gas + premium) paid separately to the router.
- Oracle: native/USD per chain (BNB/USD on BSC, POL/USD on Polygon, ETH/USD on Base/Arb/Op).

## CCIP — mainnet (verified from CCIP Directory)
| Chain | Router | Chain selector |
|---|---|---|
| BNB Chain | 0x34B03Cb9086d7D758AC55af71584F81A598759FE | 11344663589394136015 |
| Polygon | 0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe | 4051577828743386545 |
| Base | 0x881e3A65B4d4a04dD529061dd0071cf975F58bCD | 15971525489660198786 |
| Optimism | 0x3206695CaE29952f4b0c22a169725a865bc8Ce0f | 3734403246176062136 |
| Ethereum | 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D | 5009297550715157269 |

(Token Admin Registry / RMN per chain: see https://docs.chain.link/ccip/directory/mainnet)

## CCIP — BSC testnet (verified)
- Router: 0xE1053aE1857476f36A3C62580FF9b016E8EE8F6f
- Chain selector: 13264668187771770619
- RMN proxy: 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D
- Token admin registry: 0xF8f2A4466039Ac8adf9944fD67DBb3bb13888f2B
- Registry module owner: 0x8Cd87FeAC14D69D770E67Bedf029e6fd3F33D0C7
- LINK: 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06

## Native/USD oracles
| Chain | Gas token | Feed | Address |
|---|---|---|---|
| BSC mainnet | BNB | BNB/USD | 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE |
| BSC testnet | BNB | BNB/USD | 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526 |
| Polygon | **POL** | **POL/USD** | 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0 |
| Polygon Amoy | POL | POL/USD | 0x001382149eBa3441043c1c66972b4772963f5D43 |
| Ethereum | ETH | ETH/USD | 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 |
| Base/Arb/Op | ETH | ETH/USD | confirm at docs.chain.link/data-feeds |

⚠ **Polygon footgun**: gas is POL, not ETH → use POL/USD. ETH/USD also exists on
Polygon (0xF9680...) — do NOT use it (~thousand-fold mispricing).

## Ignition modules
| Module | Network | Purpose |
|---|---|---|
| MolePinDeployLocal.ts | localhost | mock feed + mock router + token + gateway |
| MolePinDeployHomeTestnet.ts | bscTestnet | home (testnet CCIP + BNB/USD) |
| MolePinDeployHome.ts | bsc | home (mainnet CCIP + BNB/USD) |
| MolePinDeployRemotePolygon.ts | polygon | remote (POL/USD); copy per chain |

New remote chain = copy MolePinDeployRemotePolygon.ts, swap router + native/USD feed.

## Deploy order
1. `deploy:bsc` (or testnet) — MolePin token + gateway on BSC.
2. Deploy LockReleaseTokenPool (CCT standard) on BSC.
3. Register token+pool in CCT Token Admin Registry (BSC).
4. Per remote: deploy MolePinRemote + gateway → grantPoolRoles(pool) → BurnMintTokenPool → registry.
5. setDestChain(selector) both directions on every gateway.
6. Configure lanes / rate limits.
(Steps 2–6 = scripts/register-cct.ts, to be written.)

## Package versions
@openzeppelin/contracts@5.x · @chainlink/contracts-ccip@1.6.x · solc 0.8.28 · Node 22 · Hardhat 3.6
