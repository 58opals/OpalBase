import Foundation
import Testing
@testable import OpalBase

@Suite("ECDSAModel SchnorrModel BCH", .tags(.unit))
struct EllipticCurveDigitalSignatureSchnorrBitcoinCashValidator {
    @Test("SchnorrModel BCH signature matches known vector")
    func schnorrBchSignatureMatchesKnownVector() throws {
        let digest32 = try Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        let privateKey32 = try Data(hexadecimalString: "0000000000000000000000000000000000000000000000000000000000000001")
        let privateKey = try PrivateKeyModel(data: privateKey32)
        let signature = try ECDSAModel.sign(message: digest32, with: privateKey, in: .schnorr)
        let expectedSignature = try Data(hexadecimalString: "d83f906d53ae57bb1a6a5e1e85a7c6b5ce93eb7dc57caeb06093ce9fa4788502" + "eb6feff7daac0b348ddd05d077a3ebc3fe3299042288c42c1be5b219a4e63f33"
        )
        
        #expect(signature == expectedSignature)
    }
    
    @Test("SchnorrModel BCH sign verify round trip")
    func schnorrBchSignVerifyRoundtrip() throws {
        let privateKey = try PrivateKeyModel()
        let publicKey = try PublicKeyModel(privateKey: privateKey)
        let preimage = Data("SchnorrModel round trip preimage".utf8)
        let message = ECDSAModel.MessageModel.makeDoubleSHA256(preimage)
        let signature = try ECDSAModel.sign(message: message, with: privateKey, in: .schnorr)
        let isValid = try ECDSAModel.verify(signature: signature,
                                       message: message,
                                       publicKey: publicKey,
                                       format: .schnorr)
        
        #expect(isValid)
    }
    
    @Test("build produces SchnorrModel-length signature push for P2PKH")
    func schnorrBchTransactionBuildsWithSchnorrSignature() throws {
        let privateKey = try PrivateKeyModel()
        let publicKey = try PublicKeyModel(privateKey: privateKey)
        let lockingScript = ScriptModel.p2pkh_OPCHECKSIG(hash: PublicKeyModel.HashModel(publicKey: publicKey)).data
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x11, count: 32))
        let unspent = TransactionModel.OutputModel.UnspentModel(value: 10_000,
                                                 lockingScript: lockingScript,
                                                 previousTransactionHash: previousTransactionHash,
                                                 previousTransactionOutputIndex: 0)
        let utxoPrivateKeyPairs = [unspent: privateKey]
        let recipientOutputs = [TransactionModel.OutputModel(value: 4_000, lockingScript: lockingScript)]
        let changeOutput = TransactionModel.OutputModel(value: 6_000, lockingScript: lockingScript)
        
        let schnorrTransaction = try TransactionModel.build(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                                                       recipientOutputs: recipientOutputs,
                                                       changeOutput: changeOutput,
                                                       outputOrderingStrategy: .privacyRandomized,
                                                       signatureFormat: .schnorr,
                                                       feePerByte: 0)
        let ecdsaTransaction = try TransactionModel.build(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                                                     recipientOutputs: recipientOutputs,
                                                     changeOutput: changeOutput,
                                                     outputOrderingStrategy: .privacyRandomized,
                                                     signatureFormat: .ecdsa(.der),
                                                     feePerByte: 0)
        let unlockingScript = try #require(schnorrTransaction.inputs.first?.unlockingScript)
        
        #expect(unlockingScript.first == 65)
        let schnorrEncodedTransaction = try schnorrTransaction.encode()
        let ecdsaEncodedTransaction = try ecdsaTransaction.encode()
        #expect(schnorrEncodedTransaction.count < ecdsaEncodedTransaction.count)
    }
}
