// SnapshotPersistenceValidator~EntrySpan.swift

import Testing
@testable import OpalBase

extension SnapshotPersistenceValidator {
    @Test("rejects excessive sparse snapshot spans without mutating address state")
    func rejectExcessiveSparseSnapshotSpanWithoutMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let originalSnapshot = await book.makeSnapshot()
        let highestIndex = HardenedIndex.maxUnhardenedValue
        let implicitEntryCount = Int(highestIndex)
        let sparseSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: [
                .init(
                    usage: .receiving,
                    index: highestIndex,
                    isUsed: true,
                    isReserved: false,
                    balance: nil,
                    lastUpdated: nil
                )
            ],
            changeEntries: [],
            utxos: [],
            transactions: []
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotEntrySpan(
            usage: .receiving,
            implicitEntryCount: implicitEntryCount,
            maximumImplicitEntryCount: OpalBase.Address.Book.maximumImplicitSnapshotEntryCount
        )) {
            try await book.refresh(with: sparseSnapshot)
        }

        #expect(await book.makeSnapshot() == originalSnapshot)
    }
}
