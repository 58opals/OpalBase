// EllipticCurveDigitalSignatureSchnorrBitcoinCashValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Cryptography.ECDSA OpalBase.Cryptography.Schnorr BCH", .tags(.unit))
struct EllipticCurveDigitalSignatureSchnorrBitcoinCashValidator {
    @Test("OpalBase.Cryptography.Schnorr BCH signature matches known vector")
    func schnorrBchSignatureMatchesKnownVector() throws {
        let digest32 = try Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        let privateKey32 = try Data(hexadecimalString: "0000000000000000000000000000000000000000000000000000000000000001")
        let privateKey = try OpalBase.PrivateKey(data: privateKey32)
        let signature = try OpalBase.Cryptography.ECDSA.sign(message: digest32, with: privateKey, in: .schnorr)
        let expectedSignature = try Data(hexadecimalString: "d83f906d53ae57bb1a6a5e1e85a7c6b5ce93eb7dc57caeb06093ce9fa4788502" + "eb6feff7daac0b348ddd05d077a3ebc3fe3299042288c42c1be5b219a4e63f33"
        )
        
        #expect(signature == expectedSignature)
    }
    
    @Test("OpalBase.Cryptography.Schnorr BCH sign verify round trip")
    func schnorrBchSignVerifyRoundtrip() throws {
        let privateKey = try OpalBase.PrivateKey()
        let publicKey = try OpalBase.PublicKey(privateKey: privateKey)
        let preimage = Data("OpalBase.Cryptography.Schnorr round trip preimage".utf8)
        let message = OpalBase.Cryptography.ECDSA.Message.makeDoubleSHA256(preimage)
        let signature = try OpalBase.Cryptography.ECDSA.sign(message: message, with: privateKey, in: .schnorr)
        let isValid = try OpalBase.Cryptography.ECDSA.verify(signature: signature,
                                       message: message,
                                       publicKey: publicKey,
                                       format: .schnorr)
        
        #expect(isValid)
    }
    
    @Test("build produces OpalBase.Cryptography.Schnorr-length signature push for P2PKH")
    func schnorrBchTransactionBuildsWithSchnorrSignature() throws {
        let privateKey = try OpalBase.PrivateKey()
        let publicKey = try OpalBase.PublicKey(privateKey: privateKey)
        let lockingScript = OpalBase.Script.p2pkh_OPCHECKSIG(hash: OpalBase.PublicKey.Hash(publicKey: publicKey)).data
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let unspent = OpalBase.Transaction.Output.Unspent(value: 10_000,
                                                 lockingScript: lockingScript,
                                                 previousTransactionHash: previousTransactionHash,
                                                 previousTransactionOutputIndex: 0)
        let utxoPrivateKeyPairs = [unspent: privateKey]
        let recipientOutputs = [OpalBase.Transaction.Output(value: 4_000, lockingScript: lockingScript)]
        let changeOutput = OpalBase.Transaction.Output(value: 6_000, lockingScript: lockingScript)
        
        let schnorrTransaction = try OpalBase.Transaction.build(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                                                       recipientOutputs: recipientOutputs,
                                                       changeOutput: changeOutput,
                                                       outputOrderingStrategy: .privacyRandomized,
                                                       signatureFormat: .schnorr,
                                                       feePerByte: 0)
        let ecdsaTransaction = try OpalBase.Transaction.build(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
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

