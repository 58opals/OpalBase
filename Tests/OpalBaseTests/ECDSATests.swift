import XCTest
@testable import OpalBase

final class ECDSATests: XCTestCase {
    func testPublicKeyGeneration() throws {
        let privateKey = try PrivateKey(data: Data(repeating: 0x01, count: 32))
        let publicKey = try PublicKey(privateKey: privateKey)
        let publicKeyFromECDSA = try ECDSA.getPublicKey(from: privateKey.rawData)
        
        XCTAssertNotNil(publicKey)
        XCTAssertEqual(publicKey.compressedData, publicKeyFromECDSA.dataRepresentation)
        XCTAssertEqual(publicKey.compressedData.count, 33)
        XCTAssertEqual(publicKeyFromECDSA.dataRepresentation.count, 33)
    }
    
    func testECDSASignatureAndVerification() throws {
        let privateKey = try PrivateKey(data: Data(repeating: 0x01, count: 32))
        let publicKey = try PublicKey(privateKey: privateKey)
        
        let message = "Hello, world!".data(using: .utf8)!
        
        let derSignature = try ECDSA.sign(message: message, with: privateKey.rawData, in: .ecdsa(.der))
        XCTAssertNotNil(derSignature)
        
        let publicKeyFromECDSA = try ECDSA.getPublicKey(from: privateKey.rawData)
        XCTAssertEqual(publicKey.compressedData, publicKeyFromECDSA.dataRepresentation)
        let isDerSignatureValid = try ECDSA.verify(signature: derSignature, message: message, publicKey: publicKey, format: .ecdsa(.der))
        XCTAssertTrue(isDerSignatureValid)
    }
    
    func testSchnorrSignatureAndVerification() throws {
        let privateKey = try PrivateKey(data: Data(repeating: 0x01, count: 32))
        let publicKey = try PublicKey(privateKey: privateKey)
        
        let message = "Hello, world!".data(using: .utf8)!
        
        let schnorrSignature = try ECDSA.sign(message: message, with: privateKey.rawData, in: .schnorr)
        XCTAssertNotNil(schnorrSignature)
        
        let isSchnorrSignatureValid = try ECDSA.verify(signature: schnorrSignature, message: message, publicKey: publicKey, format: .schnorr)
        XCTAssertTrue(isSchnorrSignatureValid)
    }
    
    func testInvalidSignatureVerification() throws {
        let privateKey = try PrivateKey(data: Data(repeating: 0x01, count: 32))
        let publicKey = try PublicKey(privateKey: privateKey)
        
        let message = "Hello, world!".data(using: .utf8)!
        let anotherMessage = "Goodbye, world!".data(using: .utf8)!
        
        // DER Signature
        let derSignature = try ECDSA.sign(message: message, with: privateKey.rawData, in: .ecdsa(.der))
        
        // Verify against a different message
        let isInvalidDerSignatureValid = try ECDSA.verify(signature: derSignature, message: anotherMessage, publicKey: publicKey, format: .ecdsa(.der))
        XCTAssertFalse(isInvalidDerSignatureValid)
        
        // Schnorr Signature
        let schnorrSignature = try ECDSA.sign(message: message, with: privateKey.rawData, in: .schnorr)
        
        // Verify against a different message
        let isInvalidSchnorrSignatureValid = try ECDSA.verify(signature: schnorrSignature, message: anotherMessage, publicKey: publicKey, format: .schnorr)
        XCTAssertFalse(isInvalidSchnorrSignatureValid)
    }
}
