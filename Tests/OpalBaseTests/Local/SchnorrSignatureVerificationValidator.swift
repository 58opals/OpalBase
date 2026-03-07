// SchnorrSignatureVerificationValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("SchnorrModel signature verification", .tags(.unit, .cryptography))
struct SchnorrSignatureVerificationValidator {
    @Test("Verify SchnorrModel signatures with Bitcoin improvement proposal vectors")
    func verifiesSchnorrSignatureVectors() throws {
        for vector in BitcoinImprovementProposalSchnorrTestData.all {
            let publicKeyData = try Data(hexadecimalString: vector.publicKeyHexadecimal)
            let publicKey = try OpalBase.PublicKey(compressedData: publicKeyData)
            let message = try Data(hexadecimalString: vector.messageHexadecimal)
            let signature = try Data(hexadecimalString: vector.signatureHexadecimal)
            
            let isValid = try ECDSAModel.verify(signature: signature,
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

