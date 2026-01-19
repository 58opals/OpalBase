import Foundation
import Testing
import SwiftSchnorr
@testable import OpalBase

@Suite("Elliptic curve digital signatures", .tags(.unit, .cryptography))
struct EllipticCurveDigitalSignatureTests {
    @Test("Distinguished Encoding Rules signatures verify with SwiftSchnorr ECDSA verifier")
    func testDistinguishedEncodingRulesSignatureVerifiesWithSwiftSchnorr() throws {
        let privateKey = try PrivateKey()
        let publicKey = try PublicKey(privateKey: privateKey)
        let message = Data("OpalBase ECDSA verification".utf8)
        
        let signature = try ECDSA.sign(message: message, with: privateKey, in: .ecdsa(.der))
        let digest = SHA256.hash(message)
        let isValid = try Secp256k1ECDSA.verify(derEncodedSignature: signature,
                                                digest32: digest,
                                                publicKey: publicKey.compressedData)
        
        #expect(isValid)
    }
    
    @Test("Distinguished Encoding Rules signatures reject mismatched messages")
    func testDistinguishedEncodingRulesSignatureRejectsMismatchedMessages() throws {
        let privateKey = try PrivateKey()
        let publicKey = try PublicKey(privateKey: privateKey)
        let message = Data("ECDSA message".utf8)
        let alteredMessage = Data("ECDSA message (altered)".utf8)
        
        let signature = try ECDSA.sign(message: message, with: privateKey, in: .ecdsa(.der))
        let alteredDigest = SHA256.hash(alteredMessage)
        let isValid = try Secp256k1ECDSA.verify(derEncodedSignature: signature,
                                                digest32: alteredDigest,
                                                publicKey: publicKey.compressedData)
        
        #expect(!isValid)
    }
}
