// KeyDerivationPathValidator.swift

import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Key.DerivationPath", .tags(.unit))
struct KeyDerivationPathValidator {
    @Test("rejects hardened address indices")
    func derivationPathRejectsHardenedAddressIndex() throws {
        let account = try OpalBase.Key.DerivationPath.Account(rawIndexInteger: 0)

        #expect(throws: OpalBase.Key.DerivationPath.Error.indexOverflow) {
            _ = try OpalBase.Key.DerivationPath(
                account: account,
                usage: .receiving,
                index: Harden.bit
            )
        }
    }
}
