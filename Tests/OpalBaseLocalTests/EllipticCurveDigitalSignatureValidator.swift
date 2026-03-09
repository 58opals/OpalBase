// EllipticCurveDigitalSignatureValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Elliptic curve digital signatures", .tags(.unit, .cryptography))
struct EllipticCurveDigitalSignatureValidator {
    @Test("Distinguished Encoding Rules signatures verify with OpalBase.Cryptography.ECDSA")
    func distinguishedEncodingRulesSignatureVerifiesWithECDSA() throws {
        let privateKey = try OpalBase.PrivateKey()
        let publicKey = try OpalBase.PublicKey(privateKey: privateKey)
        let message = Data("OpalBase OpalBase.Cryptography.ECDSA verification".utf8)
        
        let signature = try OpalBase.Cryptography.ECDSA.sign(message: message, with: privateKey, in: .ecdsa(.der))
        let digest = SHA256.hash(message)
        let isValid = try OpalBase.Cryptography.Secp256k1.verify(derEncodedSignature: signature,
                                           digest32: digest,
                                           publicKey: publicKey.compressedData)
        
        #expect(isValid)
    }
    
    @Test("Distinguished Encoding Rules signatures reject mismatched messages")
    func distinguishedEncodingRulesSignatureRejectsMismatchedMessages() throws {
        let privateKey = try OpalBase.PrivateKey()
        let publicKey = try OpalBase.PublicKey(privateKey: privateKey)
        let message = Data("OpalBase.Cryptography.ECDSA message".utf8)
        let alteredMessage = Data("OpalBase.Cryptography.ECDSA message (altered)".utf8)
        
        let signature = try OpalBase.Cryptography.ECDSA.sign(message: message, with: privateKey, in: .ecdsa(.der))
        let alteredDigest = SHA256.hash(alteredMessage)
        let isValid = try OpalBase.Cryptography.Secp256k1.verify(derEncodedSignature: signature,
                                           digest32: alteredDigest,
                                           publicKey: publicKey.compressedData)
        
        #expect(!isValid)
    }
}
