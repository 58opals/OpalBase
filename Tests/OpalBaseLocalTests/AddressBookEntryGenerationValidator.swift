// AddressBookEntryGenerationValidator.swift

import Dispatch
import Foundation
import OpalCrypto
import OpalBaseTestSupport
import Synchronization
import Testing
@testable import OpalBase
@testable import OpalBaseCore

@Suite("OpalBase.Address.Book Entry Generation", .tags(.unit, .address))
struct AddressBookEntryGenerationValidator {
    @Test("Concurrent entry generation keeps every address and derivation path unique", .timeLimit(.minutes(1)))
    func concurrentGenerationPreservesUniqueEntries() async throws {
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        let book = try await OpalBase.Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            gapLimit: 1
        )
        let publisher = await book.entryPublisher
        let hold = EntryGenerationPublisherHold()
        let publisherHold = Task {
            await publisher.holdPublishingForEntryGenerationTest(hold)
        }
        defer { hold.release.signal() }
        try await waitUntil { hold.hasStarted.withLock { $0 } }

        let firstGeneration = Task {
            try await book.generateEntries(for: .receiving, entryCount: 2, isUsed: false)
        }
        try await waitUntil { await book.countEntries(for: .receiving) >= 2 }

        // The publisher stays held while a second generation reads the next
        // derivation index. Neither generation can finish its notifications.
        let secondGeneration = Task {
            try await book.generateEntries(for: .receiving, entryCount: 1, isUsed: false)
        }
        try await waitUntil { await book.countEntries(for: .receiving) >= 3 }

        hold.release.signal()
        #expect(await publisherHold.value)
        try await firstGeneration.value
        try await secondGeneration.value

        let entries = await book.listEntries(for: .receiving)
        #expect(entries.count == 4)
        #expect(Set(entries.map(\.address)).count == 4)
        #expect(Set(entries.map(\.derivationPath)).count == 4)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                throw EntryGenerationFixtureError.suspensionNotReached
            }
            await Task.yield()
        }
    }
}

private final class EntryGenerationPublisherHold: Sendable {
    let hasStarted = Mutex(false)
    let release = DispatchSemaphore(value: 0)
}

private extension OpalBase.Address.Book.Entry.PublisherActor {
    func holdPublishingForEntryGenerationTest(_ hold: EntryGenerationPublisherHold) -> Bool {
        hold.hasStarted.withLock { $0 = true }
        return hold.release.wait(timeout: .now() + 20) == .success
    }
}

private enum EntryGenerationFixtureError: Swift.Error {
    case suspensionNotReached
}
