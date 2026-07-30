// CashCodeQualifyingInput.swift

import Foundation

struct CashCodeQualifyingInput {
    static let maximumInputCount = 30

    let index: Int
    let input: OpalBase.Transaction.Input
    let publicKey: OpalBase.Key.PublicKey

    static func collect(
        from transaction: OpalBase.Transaction
    ) -> [CashCodeQualifyingInput] {
        transaction.inputs
            .prefix(maximumInputCount)
            .enumerated()
            .compactMap { index, input in
                make(index: index, input: input)
            }
    }

    private static func make(
        index: Int,
        input: OpalBase.Transaction.Input
    ) -> CashCodeQualifyingInput? {
        guard !input.isCoinbase else { return nil }

        let bytecode = [UInt8](input.unlockingScript)
        guard let signaturePushLength = bytecode.first.map(Int.init),
              (9...73).contains(signaturePushLength),
              bytecode.count == 1 + signaturePushLength + 1 + 33
        else {
            return nil
        }

        let signatureStart = 1
        let signatureEnd = signatureStart + signaturePushLength
        let signatureWithHashType = Array(
            bytecode[signatureStart..<signatureEnd]
        )
        guard isStructurallyValidSignature(signatureWithHashType),
              bytecode[signatureEnd] == 33
        else {
            return nil
        }

        let publicKeyStart = signatureEnd + 1
        let publicKeyData = Data(
            bytecode[publicKeyStart..<(publicKeyStart + 33)]
        )
        guard let publicKey = try? OpalBase.Key.PublicKey(
            compressedData: publicKeyData
        ) else {
            return nil
        }

        return CashCodeQualifyingInput(
            index: index,
            input: input,
            publicKey: publicKey
        )
    }

    private static func isStructurallyValidSignature(
        _ signatureWithHashType: [UInt8]
    ) -> Bool {
        guard let hashType = signatureWithHashType.last,
              isSupportedHashType(hashType)
        else {
            return false
        }

        let signature = Array(signatureWithHashType.dropLast())
        if signature.count == 64 {
            return true
        }
        return isStrictDEREncodedSignature(signature)
    }

    private static func isSupportedHashType(_ value: UInt8) -> Bool {
        let mode = value & 0x1f
        let hasForkID = (value & 0x40) != 0
        let hasUnknownLowBits = (value & 0x1c) != 0
        return (1...3).contains(mode)
            && hasForkID
            && !hasUnknownLowBits
    }

    private static func isStrictDEREncodedSignature(
        _ signature: [UInt8]
    ) -> Bool {
        guard (8...72).contains(signature.count),
              signature[0] == 0x30,
              Int(signature[1]) == signature.count - 2,
              signature[2] == 0x02
        else {
            return false
        }

        let rLength = Int(signature[3])
        let rStart = 4
        let rEnd = rStart + rLength
        guard rLength > 0,
              rEnd + 2 <= signature.count,
              (signature[rStart] & 0x80) == 0,
              !(rLength > 1
                  && signature[rStart] == 0
                  && (signature[rStart + 1] & 0x80) == 0),
              signature[rEnd] == 0x02
        else {
            return false
        }

        let sLength = Int(signature[rEnd + 1])
        let sStart = rEnd + 2
        guard sLength > 0,
              sStart + sLength == signature.count,
              (signature[sStart] & 0x80) == 0,
              !(sLength > 1
                  && signature[sStart] == 0
                  && (signature[sStart + 1] & 0x80) == 0)
        else {
            return false
        }
        return true
    }
}
