// ReusablePaymentAddressDerivationValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Reusable payment address byte derivation", .tags(.unit))
struct ReusablePaymentAddressDerivationValidator {
    @Test("shared point uses the exact padded x-coordinate hash domain")
    func deriveExactSharedPointDigest() throws {
        let senderSigningKey = try ReusablePaymentAddressFixtureData
            .makeSenderSigningKey()
        let scanSigningKey = try ReusablePaymentAddressFixtureData
            .makeScanSigningKey()
        let senderDigest = try CashCodeDerivation.makeSharedPointDigest(
            signingKey: senderSigningKey,
            publicKey: scanSigningKey.publicKey
        )
        let receiverDigest = try CashCodeDerivation.makeSharedPointDigest(
            signingKey: scanSigningKey,
            publicKey: senderSigningKey.publicKey
        )

        #expect(senderDigest == receiverDigest)
        #expect(
            senderDigest.hexadecimalString
                == "8511bfa62bd512368d50e06b19348f1192a21b1943e01c5f78f633b881a438fe"
        )
    }

    @Test("outpoint text uses lowercase display-order hash and minimal decimal index")
    func deriveExactOutpointDomain() throws {
        let outpoint = try makeVectorOutpoint()

        #expect(
            try CashCodeDerivation.makeOutpointText(outpoint)
                == "abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567890"
        )
        #expect(
            try CashCodeDerivation.makeOutpointHash(outpoint).hexadecimalString
                == "aafd88e2aae427a4d0258fd4e9da82888abcbfd99404a3751da897e5c87d65d8"
        )
    }

    @Test("chain code preserves an arbitrary-precision carry before hashing")
    func deriveExactChainCode() throws {
        let sharedPointDigest = try Data(
            hexadecimalString:
                "8511bfa62bd512368d50e06b19348f1192a21b1943e01c5f78f633b881a438fe"
        )
        let outpointHash = try Data(
            hexadecimalString:
                "aafd88e2aae427a4d0258fd4e9da82888abcbfd99404a3751da897e5c87d65d8"
        )

        #expect(
            try CashCodeDerivation.makeMinimalUnsignedSum(
                sharedPointDigest,
                outpointHash
            ).hexadecimalString
                == "01300f4888d6b939db5d767040030f119a1d5edaf2d7e4bfd4969ecb9e4a219ed6"
        )
        #expect(
            try CashCodeDerivation.makeChainCode(
                sharedPointDigest: sharedPointDigest,
                outpoint: makeVectorOutpoint()
            ).hexadecimalString
                == "e4597ed066ca88ad4abb72f290251acaa5b680e574dad641b6bc4e38fbfa34b1"
        )
    }

    @Test("derivation rejects malformed fixed-width inputs")
    func rejectMalformedDerivationInputs() {
        let malformedOutpoint = OpalBase.Transaction.Outpoint(
            transactionHash: .init(naturalOrder: Data(repeating: 0, count: 31)),
            outputIndex: 0
        )

        #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .invalidOutpointTransactionHash
        ) {
            _ = try CashCodeDerivation.makeOutpointText(malformedOutpoint)
        }
        #expect(
            throws: OpalBase.ReusablePaymentAddress.Error.invalidDerivationDigest
        ) {
            _ = try CashCodeDerivation.makeMinimalUnsignedSum(
                Data(repeating: 0, count: 31),
                Data(repeating: 0, count: 32)
            )
        }
    }

    private func makeVectorOutpoint() throws -> OpalBase.Transaction.Outpoint {
        OpalBase.Transaction.Outpoint(
            transactionHash: OpalBase.Transaction.Hash(
                reverseOrder: try Data(
                    hexadecimalString:
                        "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
                )
            ),
            outputIndex: 0
        )
    }
}
