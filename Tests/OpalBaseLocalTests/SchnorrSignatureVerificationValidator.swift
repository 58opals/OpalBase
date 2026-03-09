// SchnorrSignatureVerificationValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Cryptography.Schnorr signature verification", .tags(.unit, .cryptography))
struct SchnorrSignatureVerificationValidator {
    @Test("Verify OpalBase.Cryptography.Schnorr signatures with Bitcoin improvement proposal vectors")
    func verifiesSchnorrSignatureVectors() throws {
        for vector in BitcoinImprovementProposalSchnorrTestData.all {
            let publicKeyData = try Data(hexadecimalString: vector.publicKeyHexadecimal)
            let publicKey = try OpalBase.PublicKey(compressedData: publicKeyData)
            let message = try Data(hexadecimalString: vector.messageHexadecimal)
            let signature = try Data(hexadecimalString: vector.signatureHexadecimal)
            
            let isValid = try OpalBase.Cryptography.ECDSA.verify(signature: signature,
                                           message: message,
                                           publicKey: publicKey,
                                           format: .schnorr)
            
            #expect(
                isValid == vector.isVerificationExpected,
                "Vector \(vector.index) expected \(vector.isVerificationExpected) but got \(isValid). \(vector.comment ?? "No comment.")"
            )
        }
    }
}

