import Foundation
import Testing
@testable import OpalBase

@Suite("Schnorr signature verification", .tags(.unit, .cryptography))
struct SchnorrSignatureVerificationTests {
    @Test("Verify Schnorr signatures with Bitcoin improvement proposal vectors")
    func testVerifiesSchnorrSignatureVectors() throws {
        for vector in BitcoinImprovementProposalSchnorrTestVectors.all {
            let publicKeyData = try Data(hexadecimalString: vector.publicKeyHexadecimal)
            let publicKey = try PublicKey(compressedData: publicKeyData)
            let message = try Data(hexadecimalString: vector.messageHexadecimal)
            let signature = try Data(hexadecimalString: vector.signatureHexadecimal)
            
            let isValid = try ECDSA.verify(signature: signature,
                                           message: message,
                                           publicKey: publicKey,
                                           format: .schnorr)
            
            #expect(
                isValid == vector.expectedVerificationResult,
                "Vector \(vector.index) expected \(vector.expectedVerificationResult) but got \(isValid). \(vector.comment ?? "No comment.")"
            )
        }
    }
}
