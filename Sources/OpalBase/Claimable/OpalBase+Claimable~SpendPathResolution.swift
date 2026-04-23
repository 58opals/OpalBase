// OpalBase+Claimable~SpendPathResolution.swift

import Foundation

func makeClaimableSpendPath(
    from unlockingScript: Data,
    expectedRedeemScriptData: Data
) -> OpalBase.Claimable.SpendPath? {
    let bytes = Array(unlockingScript)
    var offset = 0

    guard (try? readClaimablePushedElement(from: bytes, offset: &offset)) != nil,
          (try? readClaimablePushedElement(from: bytes, offset: &offset)) != nil,
          offset < bytes.count
    else {
        return nil
    }

    let branchOpcode = bytes[offset]
    offset += 1

    guard let redeemScriptData = try? readClaimablePushedElement(from: bytes, offset: &offset),
          redeemScriptData == expectedRedeemScriptData,
          offset == bytes.count
    else {
        return nil
    }

    switch branchOpcode {
    case ScriptOperationCode._1.rawValue:
        return .claim
    case ScriptOperationCode._0.rawValue:
        return .refund
    default:
        return nil
    }
}

func readClaimablePushedElement(
    from bytes: [UInt8],
    offset: inout Int
) throws -> Data {
    guard offset < bytes.count else {
        throw Data.Error.indexOutOfRange
    }

    let opcode = bytes[offset]
    offset += 1

    let count: Int
    switch opcode {
    case 0 ... 75:
        count = Int(opcode)
    case ScriptOperationCode._PUSHDATA1.rawValue:
        guard offset < bytes.count else {
            throw Data.Error.indexOutOfRange
        }
        count = Int(bytes[offset])
        offset += 1
    case ScriptOperationCode._PUSHDATA2.rawValue:
        guard offset + 1 < bytes.count else {
            throw Data.Error.indexOutOfRange
        }
        count = Int(UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
        offset += 2
    case ScriptOperationCode._PUSHDATA4.rawValue:
        guard offset + 3 < bytes.count else {
            throw Data.Error.indexOutOfRange
        }
        count = Int(
            UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        )
        offset += 4
    default:
        throw Data.Error.indexOutOfRange
    }

    guard offset + count <= bytes.count else {
        throw Data.Error.indexOutOfRange
    }

    let element = Data(bytes[offset ..< offset + count])
    offset += count
    return element
}
