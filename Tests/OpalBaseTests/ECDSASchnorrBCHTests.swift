import Foundation
import Testing
@testable import OpalBase

@Suite("ECDSA Schnorr BCH", .tags(.unit))
struct ECDSASchnorrBCHTests {
    @Test("Schnorr BCH signature matches known vector")
    func testSchnorrBchSignatureMatchesKnownVector() throws {
        let digest32 = try Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        let privateKey32 = try Data(hexadecimalString: "0000000000000000000000000000000000000000000000000000000000000001")
        let privateKey = try PrivateKey(data: privateKey32)
        let signature = try ECDSA.sign(message: digest32, with: privateKey, in: .schnorr)
        let expectedSignature = try Data(hexadecimalString: "d83f906d53ae57bb1a6a5e1e85a7c6b5ce93eb7dc57caeb06093ce9fa4788502" + "eb6feff7daac0b348ddd05d077a3ebc3fe3299042288c42c1be5b219a4e63f33"
        )
        
        #expect(signature == expectedSignature)
    }
    
    @Test("Schnorr BCH sign verify round trip")
    func testSchnorrBchSignVerifyRoundtrip() throws {
        let privateKey = try PrivateKey()
        let publicKey = try PublicKey(privateKey: privateKey)
        let preimage = Data("Schnorr round trip preimage".utf8)
        let message = ECDSA.Message.makeDoubleSHA256(preimage)
        let signature = try ECDSA.sign(message: message, with: privateKey, in: .schnorr)
        let isValid = try ECDSA.verify(signature: signature,
                                       message: message,
                                       publicKey: publicKey,
                                       format: .schnorr)
        
        #expect(isValid)
    }
    
    @Test("build produces Schnorr-length signature push for P2PKH")
    func testSchnorrBchTransactionBuildsWithSchnorrSignature() throws {
        let privateKey = try PrivateKey()
        let publicKey = try PublicKey(privateKey: privateKey)
        let lockingScript = Script.p2pkh_OPCHECKSIG(hash: PublicKey.Hash(publicKey: publicKey)).data
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let unspent = Transaction.Output.Unspent(value: 10_000,
                                                 lockingScript: lockingScript,
                                                 previousTransactionHash: previousTransactionHash,
                                                 previousTransactionOutputIndex: 0)
        let utxoPrivateKeyPairs = [unspent: privateKey]
        let recipientOutputs = [Transaction.Output(value: 4_000, lockingScript: lockingScript)]
        let changeOutput = Transaction.Output(value: 6_000, lockingScript: lockingScript)
        
        let schnorrTransaction = try Transaction.build(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                                                       recipientOutputs: recipientOutputs,
                                                       changeOutput: changeOutput,
                                                       outputOrderingStrategy: .privacyRandomized,
                                                       signatureFormat: .schnorr,
                                                       feePerByte: 0)
        let ecdsaTransaction = try Transaction.build(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                                                     recipientOutputs: recipientOutputs,
                                                     changeOutput: changeOutput,
                                                     outputOrderingStrategy: .privacyRandomized,
                                                     signatureFormat: .ecdsa(.der),
                                                     feePerByte: 0)
        let unlockingScript = try #require(schnorrTransaction.inputs.first?.unlockingScript)
        
        #expect(unlockingScript.first == 65)
        #expect(schnorrTransaction.encode().count < ecdsaTransaction.encode().count)
    }
}
