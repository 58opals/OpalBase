import Testing
import Foundation
@testable import OpalBase

@Suite("ECDSA Tests")
struct ECDSATests {}

extension ECDSATests {
    @Test func testPublicKeyGeneration() throws {
        let privateKey = try PrivateKey(data: Data(repeating: 0x01, count: 32))
        let publicKey = try PublicKey(privateKey: privateKey)
        let publicKeyFromECDSA = try ECDSA.getPublicKey(from: privateKey.rawData)
        
        #expect(publicKey.compressedData == publicKeyFromECDSA.dataRepresentation, "Public key data mismatch.")
        #expect(publicKey.compressedData.count == 33, "Compressed public key should be 33 bytes.")
        #expect(publicKeyFromECDSA.dataRepresentation.count == 33, "Public key from ECDSA should be 33 bytes.")
    }
    
    @Test func testECDSASignatureAndVerification() throws {
        let privateKey = try PrivateKey(data: Data(repeating: 0x01, count: 32))
        let publicKey = try PublicKey(privateKey: privateKey)
        
        let message = "Hello, world!".data(using: .utf8)!
        
        let derSignature = try ECDSA.sign(message: message, with: privateKey.rawData, in: .ecdsa(.der))
        
        let publicKeyFromECDSA = try ECDSA.getPublicKey(from: privateKey.rawData)
        #expect(publicKey.compressedData == publicKeyFromECDSA.dataRepresentation, "Public key data mismatch.")
        
        let isDERSignatureValid = try ECDSA.verify(signature: derSignature, message: message, publicKey: publicKey, format: .ecdsa(.der))
        #expect(isDERSignatureValid, "DER signature verification failed.")
    }
    
    @Test func testSchnorrSignatureAndVerification() throws {
        let privateKey = try PrivateKey(data: Data(repeating: 0x01, count: 32))
        let publicKey = try PublicKey(privateKey: privateKey)
        
        let message = "Hello, world!".data(using: .utf8)!
        
        let schnorrSignature = try ECDSA.sign(message: message, with: privateKey.rawData, in: .schnorr)
        
        let isSchnorrSignatureValid = try ECDSA.verify(signature: schnorrSignature, message: message, publicKey: publicKey, format: .schnorr)
        #expect(isSchnorrSignatureValid, "Schnorr signature verification failed.")
    }
    
    @Test func testInvalidSignatureVerification() throws {
        let privateKey = try PrivateKey(data: Data(repeating: 0x01, count: 32))
        let publicKey = try PublicKey(privateKey: privateKey)
        
        let message = "Hello, world!".data(using: .utf8)!
        let anotherMessage = "Goodbye, world!".data(using: .utf8)!
        
        // DER Signature
        let derSignature = try ECDSA.sign(message: message, with: privateKey.rawData, in: .ecdsa(.der))
        // Verify against a different message
        let isInvalidDerSignatureValid = try ECDSA.verify(signature: derSignature, message: anotherMessage, publicKey: publicKey, format: .ecdsa(.der))
        #expect(!isInvalidDerSignatureValid, "DER signature verification should fail with a different message.")
        
        // Schnorr Signature
        let schnorrSignature = try ECDSA.sign(message: message, with: privateKey.rawData, in: .schnorr)
        // Verify against a different message
        let isInvalidSchnorrSignatureValid = try ECDSA.verify(signature: schnorrSignature, message: anotherMessage, publicKey: publicKey, format: .schnorr)
        #expect(!isInvalidSchnorrSignatureValid, "Schnorr signature verification should fail with a different message.")
    }
}
