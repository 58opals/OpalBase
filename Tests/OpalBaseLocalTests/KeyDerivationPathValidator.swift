// KeyDerivationPathValidator.swift

import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Key.DerivationPath", .tags(.unit))
struct KeyDerivationPathValidator {
    @Test(
        "hardened indices round-trip to their unhardened values",
        arguments: [UInt32(0), UInt32(44), UInt32(145), HardenedIndex.maxUnhardenedValue]
    )
    func hardenedIndicesRoundTripToUnhardenedValues(index: UInt32) throws {
        let hardenedIndex = try index.harden()

        #expect(try hardenedIndex.unharden() == index)
    }

    @Test("rejects hardened address indices")
    func derivationPathRejectsHardenedAddressIndex() throws {
        let account = try OpalBase.Key.DerivationPath.Account(rawIndexInteger: 0)

        #expect(throws: OpalBase.Key.DerivationPath.Error.indexOverflow) {
            _ = try OpalBase.Key.DerivationPath(
                account: account,
                usage: .receiving,
                index: HardenedIndex.bit
            )
        }
    }
}
