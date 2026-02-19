import Foundation
import Testing
@testable import OpalBase

@Suite("Schnorr signature verification", .tags(.unit, .cryptography))
struct SchnorrSignatureVerificationValidator {
    @Test("Verify Schnorr signatures with Bitcoin improvement proposal vectors")
    func verifiesSchnorrSignatureVectors() throws {
        for vector in BitcoinImprovementProposalSchnorrTestData.all {
            let publicKeyData = try Data(hexadecimalString: vector.publicKeyHexadecimal)
            let publicKey = try PublicKey(compressedData: publicKeyData)
            let message = try Data(hexadecimalString: vector.messageHexadecimal)
            let signature = try Data(hexadecimalString: vector.signatureHexadecimal)
            
            let isValid = try ECDSA.verify(signature: signature,
                                           message: message,
                                           publicKey: publicKey,
                                           format: .schnorr)
            
            #expect(
                isValid == vector.isVerificationExpected,
                "VectorData \(vector.index) expected \(vector.isVerificationExpected) but got \(isValid). \(vector.comment ?? "No comment.")"
            )
        }
    }
}
