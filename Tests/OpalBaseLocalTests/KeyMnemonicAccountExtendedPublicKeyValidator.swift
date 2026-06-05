// KeyMnemonicAccountExtendedPublicKeyValidator.swift

import OpalCrypto
import OpalBase
import OpalBaseTestSupport
import Testing

@Suite("OpalBase.Key.Mnemonic account extended public keys", .tags(.unit))
struct KeyMnemonicAccountExtendedPublicKeyValidator {
    @Test("account xpub serialization is stable for a known mnemonic and path")
    func accountExtendedPublicKeySerializationIsStable() throws {
        let serialized = try Self.makeSerializedAccountExtendedPublicKey()

        #expect(serialized == Self.expectedAccountExtendedPublicKey)
    }

    @Test("account boundary uses hardened account derivation")
    func accountBoundaryUsesHardenedAccountDerivation() throws {
        let serialized = try Self.makeSerializedAccountExtendedPublicKey()
        let extendedPublicKey = try OpalCrypto.Key.ExtendedPublic(serialized)

        #expect(extendedPublicKey.depth == 3)
        #expect(extendedPublicKey.childIndex == 0x8000_0000)
    }

    @Test("non-zero account input is hardened at the account boundary")
    func nonZeroAccountInputUsesHardenedAccountBoundary() throws {
        let serialized = try Self.makeSerializedAccountExtendedPublicKey(account: 1)
        let extendedPublicKey = try OpalCrypto.Key.ExtendedPublic(serialized)

        #expect(extendedPublicKey.depth == 3)
        #expect(extendedPublicKey.childIndex == 0x8000_0001)
        #expect(serialized != Self.expectedAccountExtendedPublicKey)
    }

    @Test("returned account xpub parses and derives non-hardened receiving children")
    func accountExtendedPublicKeyDerivesNonHardenedReceivingChildren() throws {
        let serialized = try Self.makeSerializedAccountExtendedPublicKey()
        let receivingChild = try OpalCrypto.Key.ExtendedPublic(serialized).derived(indices: [
            OpalBase.Key.DerivationPath.Usage.receiving.unhardenedIndex,
            0
        ])

        #expect(receivingChild.serialize() == Self.expectedFirstReceivingExtendedPublicKey)
    }

    @Test("raw account input rejects hardened-range values before derivation")
    func accountExtendedPublicKeyRejectsHardenedRangeAccountInput() throws {
        #expect(throws: OpalBase.Key.DerivationPath.Error.indexOverflow) {
            _ = try Self.makeMnemonic().makeSerializedAccountExtendedPublicKey(account: UInt32.max)
        }
    }

    private static func makeSerializedAccountExtendedPublicKey(account: UInt32 = 0) throws -> String {
        try makeMnemonic().makeSerializedAccountExtendedPublicKey(account: account)
    }

    private static func makeMnemonic() throws -> OpalBase.Key.Mnemonic {
        try OpalBase.Key.Mnemonic(
            phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            language: .english
        )
    }

    private static let expectedAccountExtendedPublicKey = "xpub6ByHsPNSQXTWZ7PLESMY2FufyYWtLXagSUpMQq7Un96SiThZH2iJB1X7pwviH1WtKVeDP6K8d6xxFzzoaFzF3s8BKCZx8oEDdDkNnp4owAZ"
    private static let expectedFirstReceivingExtendedPublicKey = "xpub6FzaFYeC1izfUn7tJkJRzxrFz47DK3bbE8UPhUaqBqES5pHKdPVTUqMJnALA2sy4tAUNofeWUVEydbS8TXYp89mdwfXw3NG4sUNmZ9bEh6R"
}
