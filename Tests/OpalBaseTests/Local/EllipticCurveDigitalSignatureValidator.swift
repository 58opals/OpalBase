// EllipticCurveDigitalSignatureValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Elliptic curve digital signatures", .tags(.unit, .cryptography))
struct EllipticCurveDigitalSignatureValidator {
    @Test("Distinguished Encoding Rules signatures verify with SwiftSchnorr ECDSAModel verifier")
    func distinguishedEncodingRulesSignatureVerifiesWithSwiftSchnorr() throws {
        let privateKey = try OpalBase.PrivateKey()
        let publicKey = try OpalBase.PublicKey(privateKey: privateKey)
        let message = Data("OpalBase ECDSAModel verification".utf8)
        
        let signature = try ECDSAModel.sign(message: message, with: privateKey, in: .ecdsa(.der))
        let digest = SHA256Model.hash(message)
        let isValid = try Secp256k1Model.verify(derEncodedSignature: signature,
                                           digest32: digest,
                                           publicKey: publicKey.compressedData)
        
        #expect(isValid)
    }
    
    @Test("Distinguished Encoding Rules signatures reject mismatched messages")
    func distinguishedEncodingRulesSignatureRejectsMismatchedMessages() throws {
        let privateKey = try OpalBase.PrivateKey()
        let publicKey = try OpalBase.PublicKey(privateKey: privateKey)
        let message = Data("ECDSAModel message".utf8)
        let alteredMessage = Data("ECDSAModel message (altered)".utf8)
        
        let signature = try ECDSAModel.sign(message: message, with: privateKey, in: .ecdsa(.der))
        let alteredDigest = SHA256Model.hash(alteredMessage)
        let isValid = try Secp256k1Model.verify(derEncodedSignature: signature,
                                           digest32: alteredDigest,
                                           publicKey: publicKey.compressedData)
        
        #expect(!isValid)
    }
}

