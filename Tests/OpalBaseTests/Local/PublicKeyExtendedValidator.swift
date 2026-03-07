// PublicKeyExtendedValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.PublicKey.ExtendedModel", .tags(.unit, .key))
struct PublicKeyExtendedValidator {
    @Test("serialize encodes the mainnet version prefix")
    func serializeEncodesMainnetVersionPrefix() throws {
        let mnemonic = try OpalBase.Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootKey = try OpalBase.PrivateKey.ExtendedModel.Root(seed: mnemonic.seed)
        let extendedPrivateKey = OpalBase.PrivateKey.ExtendedModel(rootKey: rootKey)
        let extendedPublicKey = try OpalBase.PublicKey.ExtendedModel(extendedPrivateKey: extendedPrivateKey)
        
        let serialized = extendedPublicKey.serialize()
        let prefix = serialized.prefix(4)
        
        #expect(prefix == Data([0x04, 0x88, 0xB2, 0x1E]))
    }
    
    @Test("init rejects invalid format and length")
    func initRejectsInvalidFormatAndLength() throws {
        #expect(throws: OpalBase.PublicKey.Error.invalidFormat) {
            _ = try OpalBase.PublicKey.ExtendedModel(xpub: "xpub0invalidformat")
        }
        
        let invalidLengthData = Data(repeating: 0x01, count: 10)
        let invalidLengthString = Base58Model.encode(invalidLengthData)
        
        #expect(throws: OpalBase.PublicKey.Error.invalidLength) {
            _ = try OpalBase.PublicKey.ExtendedModel(xpub: invalidLengthString)
        }
    }
}

