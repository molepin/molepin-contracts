// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title MolePinLzOptions
 * @notice Minimal, self-contained builder for LayerZero v2 TYPE_3 execution options.
 *         Produces the EXACT same bytes as the LayerZero OptionsBuilder
 *         .newOptions().addExecutorLzReceiveOption(gas, value) and as the off-chain
 *         scripts/lz-options.js builder. All three MUST agree byte-for-byte.
 *         (KO: LayerZero v2 TYPE_3 옵션 인코더. LZ 공식 OptionsBuilder 및 오프체인
 *          JS 빌더와 바이트 단위로 동일한 결과를 내야 함.)
 *
 * @dev Declared standalone (no LayerZero import) for the same reason the CCT
 *      gateway inlined Client types: avoid OZ/LZ version-pinning clashes and keep the
 *      gateway dependency-light. Format verified against LayerZero-v2 OptionsBuilder.sol:
 *        newOptions()          = TYPE_3 (uint16)                         → 0x0003
 *        addExecutorOption     = WORKER_ID | size(uint16) | optType | body
 *        encodeLzReceiveOption = gas(uint128) [| value(uint128)]   (value only if > 0)
 *        size                  = len(body) + 1   (+1 for the optionType byte)
 */
library MolePinLzOptions {
    uint16 internal constant TYPE_3 = 3;
    uint8  internal constant WORKER_ID_EXECUTOR = 1;
    uint8  internal constant OPTION_TYPE_LZRECEIVE = 1;

    /// @notice Build TYPE_3 options carrying a single lzReceive executor option.
    /// @param gas   gasLimit for the destination lzReceive (OFT _credit/mint).
    /// @param value native msg.value forwarded to lzReceive (usually 0 for MOL bridging).
    function lzReceive(uint128 gas, uint128 value) internal pure returns (bytes memory) {
        // option body: gas (16B) [+ value (16B) iff value > 0], mirroring
        // ExecutorOptions.encodeLzReceiveOption.
        bytes memory body = value > 0
            ? abi.encodePacked(gas, value)
            : abi.encodePacked(gas);

        uint16 size = uint16(body.length) + 1; // +1 for optionType

        return abi.encodePacked(
            TYPE_3,                 // uint16 header
            WORKER_ID_EXECUTOR,     // uint8  0x01
            size,                   // uint16 size
            OPTION_TYPE_LZRECEIVE,  // uint8  0x01
            body                    // gas [+ value]
        );
    }

    /// @notice Convenience: lzReceive option with value = 0.
    function lzReceive(uint128 gas) internal pure returns (bytes memory) {
        return lzReceive(gas, 0);
    }
}
