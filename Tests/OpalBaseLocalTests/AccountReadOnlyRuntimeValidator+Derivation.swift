// AccountReadOnlyRuntimeValidator+Derivation.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

extension AccountReadOnlyRuntimeValidator {
    @Test("read-only account derives receive and change addresses matching private runtime")
    func verifyReadOnlyAccountDerivesAddressesMatchingPrivateRuntime() async throws {
        let privateAccount = try await AccountTestFixtures.makeAccount()
        let readOnlyAccount = try await Self.makeReadOnlyAccount(from: privateAccount)

        let privateReceiving = try await privateAccount.selectNextDerivedAddress(for: .receiving)
        let readOnlyReceiving = try await readOnlyAccount.selectNextDerivedAddress(for: .receiving)
        let privateChange = try await privateAccount.selectNextDerivedAddress(for: .change)
        let readOnlyChange = try await readOnlyAccount.selectNextDerivedAddress(for: .change)

        #expect(await privateAccount.id == readOnlyAccount.id)
        #expect(privateReceiving.address == readOnlyReceiving.address)
        #expect(privateReceiving.derivationPath == readOnlyReceiving.derivationPath)
        #expect(privateChange.address == readOnlyChange.address)
        #expect(privateChange.derivationPath == readOnlyChange.derivationPath)

        let privateReserved = try await privateAccount.reserveNextReceivingDerivedAddress()
        let readOnlyReserved = try await readOnlyAccount.reserveNextReceivingDerivedAddress()
        let privateGapGenerated = try #require(await privateAccount.listDerivedAddresses(for: .receiving).first {
            $0.derivationPath.index == 20
        })
        let readOnlyGapGenerated = try #require(await readOnlyAccount.listDerivedAddresses(for: .receiving).first {
            $0.derivationPath.index == 20
        })

        #expect(privateReserved.address == readOnlyReserved.address)
        #expect(privateReserved.derivationPath == readOnlyReserved.derivationPath)
        #expect(privateGapGenerated.address == readOnlyGapGenerated.address)
        #expect(privateGapGenerated.derivationPath == readOnlyGapGenerated.derivationPath)
    }
}
