import Foundation
import Testing
@testable import OpalBase

@Suite("PrivateKeyModel.ExtendedModel", .tags(.unit, .key))
struct PrivateKeyExtendedValidator {
    @Test("serialize encodes the mainnet version prefix")
    func serializeEncodesMainnetVersionPrefix() throws {
        let mnemonic = try MnemonicModel(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootKey = try PrivateKeyModel.ExtendedModel.RootModel(seed: mnemonic.seed)
        let extendedPrivateKey = PrivateKeyModel.ExtendedModel(rootKey: rootKey)
        
        let serialized = extendedPrivateKey.serialize()
        let prefix = serialized.prefix(4)
        
        #expect(prefix == Data([0x04, 0x88, 0xAD, 0xE4]))
    }
    
    @Test("init rejects invalid format and length")
    func initRejectsInvalidFormatAndLength() throws {
        #expect(throws: PrivateKeyModel.Error.invalidFormat) {
            _ = try PrivateKeyModel.ExtendedModel(xprv: "xprv0invalidformat")
        }
        
        let invalidLengthData = Data(repeating: 0x01, count: 10)
        let invalidLengthString = Base58Model.encode(invalidLengthData)
        
        #expect(throws: PrivateKeyModel.Error.invalidLength) {
            _ = try PrivateKeyModel.ExtendedModel(xprv: invalidLengthString)
        }
    }
}
