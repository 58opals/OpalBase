// PrivateKeyExtendedValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.PrivateKey.ExtendedModel", .tags(.unit, .key))
struct PrivateKeyExtendedValidator {
    @Test("serialize encodes the mainnet version prefix")
    func serializeEncodesMainnetVersionPrefix() throws {
        let mnemonic = try OpalBase.Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootKey = try OpalBase.PrivateKey.ExtendedModel.Root(seed: mnemonic.seed)
        let extendedPrivateKey = OpalBase.PrivateKey.ExtendedModel(rootKey: rootKey)
        
        let serialized = extendedPrivateKey.serialize()
        let prefix = serialized.prefix(4)
        
        #expect(prefix == Data([0x04, 0x88, 0xAD, 0xE4]))
    }
    
    @Test("init rejects invalid format and length")
    func initRejectsInvalidFormatAndLength() throws {
        #expect(throws: OpalBase.PrivateKey.Error.invalidFormat) {
            _ = try OpalBase.PrivateKey.ExtendedModel(xprv: "xprv0invalidformat")
        }
        
        let invalidLengthData = Data(repeating: 0x01, count: 10)
        let invalidLengthString = Base58Model.encode(invalidLengthData)
        
        #expect(throws: OpalBase.PrivateKey.Error.invalidLength) {
            _ = try OpalBase.PrivateKey.ExtendedModel(xprv: invalidLengthString)
        }
    }
}

