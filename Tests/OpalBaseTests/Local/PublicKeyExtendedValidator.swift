import Foundation
import Testing
@testable import OpalBase

@Suite("PublicKeyModel.ExtendedModel", .tags(.unit, .key))
struct PublicKeyExtendedValidator {
    @Test("serialize encodes the mainnet version prefix")
    func serializeEncodesMainnetVersionPrefix() throws {
        let mnemonic = try MnemonicModel(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootKey = try PrivateKeyModel.ExtendedModel.RootModel(seed: mnemonic.seed)
        let extendedPrivateKey = PrivateKeyModel.ExtendedModel(rootKey: rootKey)
        let extendedPublicKey = try PublicKeyModel.ExtendedModel(extendedPrivateKey: extendedPrivateKey)
        
        let serialized = extendedPublicKey.serialize()
        let prefix = serialized.prefix(4)
        
        #expect(prefix == Data([0x04, 0x88, 0xB2, 0x1E]))
    }
    
    @Test("init rejects invalid format and length")
    func initRejectsInvalidFormatAndLength() throws {
        #expect(throws: PublicKeyModel.Error.invalidFormat) {
            _ = try PublicKeyModel.ExtendedModel(xpub: "xpub0invalidformat")
        }
        
        let invalidLengthData = Data(repeating: 0x01, count: 10)
        let invalidLengthString = Base58Model.encode(invalidLengthData)
        
        #expect(throws: PublicKeyModel.Error.invalidLength) {
            _ = try PublicKeyModel.ExtendedModel(xpub: invalidLengthString)
        }
    }
}
