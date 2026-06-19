# Deployments

MolePin (MOL) is deployed across 7 EVM chains using Chainlink CCT
(Cross-Chain Token standard): a LockRelease pool on the home chain (BNB Smart Chain)
and BurnMint pools on the 6 remote chains. All cross-chain transfers are routed
through Chainlink CCIP.

The token and gateway contracts share **identical addresses** across chains
(via CREATE2 / CreateX), which is a core branding requirement.

---

## Token Contracts

### MolePin — Home Token (BNB Smart Chain)

| Chain | Chain ID | Address |
|-------|----------|---------|
| BNB Smart Chain | 56 | [`0x694203c357E76F550fd009F8F2FEdC6d6E53C59E`](https://bscscan.com/address/0x694203c357E76F550fd009F8F2FEdC6d6E53C59E) |

Fixed total supply: **6,942,420,888,888 MOL** (invariant).

### MolePinRemote — Remote Token (6 chains, identical address)

`0x6942aD53c8558339bCc0E27dB7D28ee2976f506C`

| Chain | Chain ID | Explorer |
|-------|----------|----------|
| Ethereum | 1 | [Etherscan](https://etherscan.io/address/0x6942aD53c8558339bCc0E27dB7D28ee2976f506C) |
| Polygon | 137 | [PolygonScan](https://polygonscan.com/address/0x6942aD53c8558339bCc0E27dB7D28ee2976f506C) |
| Arbitrum One | 42161 | [Arbiscan](https://arbiscan.io/address/0x6942aD53c8558339bCc0E27dB7D28ee2976f506C) |
| Optimism | 10 | [Optimistic Etherscan](https://optimistic.etherscan.io/address/0x6942aD53c8558339bCc0E27dB7D28ee2976f506C) |
| Base | 8453 | [BaseScan](https://basescan.org/address/0x6942aD53c8558339bCc0E27dB7D28ee2976f506C) |
| Avalanche C-Chain | 43114 | [SnowTrace](https://snowtrace.io/address/0x6942aD53c8558339bCc0E27dB7D28ee2976f506C) |

---

## Bridge Gateway

### MolePinBridgeGateway (7 chains, identical address)

`0x6942898A893cf7065b33218A840bFE8AEbc38f70`

| Chain | Chain ID | Explorer |
|-------|----------|----------|
| BNB Smart Chain | 56 | [BscScan](https://bscscan.com/address/0x6942898A893cf7065b33218A840bFE8AEbc38f70) |
| Ethereum | 1 | [Etherscan](https://etherscan.io/address/0x6942898A893cf7065b33218A840bFE8AEbc38f70) |
| Polygon | 137 | [PolygonScan](https://polygonscan.com/address/0x6942898A893cf7065b33218A840bFE8AEbc38f70) |
| Arbitrum One | 42161 | [Arbiscan](https://arbiscan.io/address/0x6942898A893cf7065b33218A840bFE8AEbc38f70) |
| Optimism | 10 | [Optimistic Etherscan](https://optimistic.etherscan.io/address/0x6942898A893cf7065b33218A840bFE8AEbc38f70) |
| Base | 8453 | [BaseScan](https://basescan.org/address/0x6942898A893cf7065b33218A840bFE8AEbc38f70) |
| Avalanche C-Chain | 43114 | [SnowTrace](https://snowtrace.io/address/0x6942898A893cf7065b33218A840bFE8AEbc38f70) |

Per-transfer fee (native, not deducted from MOL): **$1** on BSC/Ethereum,
**$0.10** on the five L2 chains.

---

## Chainlink CCT Token Pools

Standard, unmodified Chainlink CCIP pools (v1.6.1). Verify the contract type
on-chain via `typeAndVersion()`.

| Chain | Pool Type | Address |
|-------|-----------|---------|
| BNB Smart Chain (56) | LockReleaseTokenPool 1.6.1 | `0xd00557c8636a7c3482a042ef8af62016a85582f9` |
| Ethereum (1) | BurnMintTokenPool 1.6.1 | `0xd00557c8636a7c3482a042ef8af62016a85582f9` |
| Polygon (137) | BurnMintTokenPool 1.6.1 | `0xd00557c8636a7c3482a042ef8af62016a85582f9` |
| Arbitrum One (42161) | BurnMintTokenPool 1.6.1 | `0xd00557c8636a7c3482a042ef8af62016a85582f9` |
| Optimism (10) | BurnMintTokenPool 1.6.1 | `0xd00557c8636a7c3482a042ef8af62016a85582f9` |
| Base (8453) | BurnMintTokenPool 1.6.1 | `0xd00557c8636a7c3482a042ef8af62016a85582f9` |
| Avalanche C-Chain (43114) | BurnMintTokenPool 1.6.1 | `0xc7796d3ff595ee8e4869548b833da1c98805b0d1` |

---

## Roles

| Role | Address |
|------|---------|
| Owner / Admin | `0x694268684de1720D83d8A76D2757b60B3211E385` |
| Treasury (fee recipient) | `0x69422883571c384A3EDA9A28a6318D8E4c6a1F77` |
| Deployer | `0xe146875c49F06AabC86f6CaF273c7858d988eEC8` |

---

## Verification

All contracts are source-verified on the respective block explorers.
Click any explorer link above and open the **Contract** / `#code` tab.

---

## Security & Audit

MolePin has been audited by **Beosin** (Report No. 202606191626).
All custom contracts (MolePin, MolePinRemote, MolePinBridgeGateway) are
source-verified on every chain.

Key security properties:
- **Fixed supply invariant**: home token total supply is permanently
  6,942,420,888,888 MOL; the BSC LockRelease pool's locked balance always
  equals the sum of remote-chain circulating supply.
- **Pool-only mint/burn**: remote tokens can only be minted/burned by the
  CCT pool. The temporary owner MINTER role used for first-write priming was
  revoked on all remote chains.
- **Native fees**: bridge fees are paid in the chain's native token (BNB, ETH,
  POL, etc.), never deducted from the user's MOL.

---

# 배포 정보 (한국어)

MolePin(MOL)은 Chainlink CCT(Cross-Chain Token) 방식으로 7개 EVM 체인에 배포되어
있습니다. 홈 체인(BNB 스마트 체인)은 LockRelease 풀을, 6개 원격 체인은 BurnMint
풀을 사용하며, 모든 크로스체인 전송은 Chainlink CCIP를 통해 처리됩니다.

토큰과 게이트웨이 컨트랙트는 CREATE2/CreateX를 통해 **모든 체인에서 동일한 주소**를
유지합니다 (브랜드 핵심 요건).

## 주요 주소

| 항목 | 주소 |
|------|------|
| 홈토큰 MolePin (BSC) | `0x694203c357E76F550fd009F8F2FEdC6d6E53C59E` |
| 리모트토큰 MolePinRemote (6체인 동일) | `0x6942aD53c8558339bCc0E27dB7D28ee2976f506C` |
| 게이트웨이 MolePinBridgeGateway (7체인 동일) | `0x6942898A893cf7065b33218A840bFE8AEbc38f70` |
| CCT 풀 — LockRelease (BSC) | `0xd00557c8636a7c3482a042ef8af62016a85582f9` |
| CCT 풀 — BurnMint (5개 EVM 원격) | `0xd00557c8636a7c3482a042ef8af62016a85582f9` |
| CCT 풀 — BurnMint (Avalanche) | `0xc7796d3ff595ee8e4869548b833da1c98805b0d1` |

## 핵심 특성

- **고정 공급 불변**: 홈토큰 총공급량은 6,942,420,888,888 MOL로 영구 고정.
  BSC LockRelease 풀의 잠금 잔액 = 모든 원격 체인 유통량의 합.
- **풀 전용 mint/burn**: 원격 토큰은 CCT 풀만 발행/소각 가능. (프라이밍용 임시
  owner MINTER 권한은 모든 원격 체인에서 회수 완료.)
- **네이티브 피**: 브리지 수수료는 각 체인의 네이티브 토큰(BNB/ETH/POL 등)으로
  지불되며, 사용자의 MOL에서 차감되지 않습니다.
- **수수료**: BSC/Ethereum $1, 5개 L2 체인 $0.1.
- **감사**: Beosin 감사 완료 (보고서 번호 202606191626).