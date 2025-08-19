import Testing
import Foundation
import SwiftFulcrum
@testable import OpalBase

/// Tests covering balance monitoring behavior.
@Suite("Balance Monitoring")
struct AddressBalanceMonitorTests {
    /// Account under test.
    var account: Account

    /// Creates a fresh account and starts the underlying Fulcrum service.
    init() async throws {
        let wallet = Wallet(mnemonic: try .init())
        try await wallet.addAccount(unhardenedIndex: 0)
        self.account = try await wallet.getAccount(unhardenedIndex: 0)

        let fulcrum = try await account.fulcrumPool.getFulcrum()
        try await fulcrum.start()
    }

    /// Ensures monitoring fails when no addresses exist.
    @Test func testMonitorBalancesThrowsOnEmptyAddressBook() async throws {
        await account.addressBook.clearEntries()
        
        await #expect(throws: Account.Monitor.Error.emptyAddresses) {
            _ = try await account.monitorBalances()
        }
    }

    /// Verifies a stream is produced when monitoring begins.
    @Test func testMonitorBalancesStartsStream() async throws {
        let stream = try await account.monitorBalances()
        _ = stream.makeAsyncIterator()
        await account.stopBalanceMonitoring()
    }
}

extension Address.Book {
    /// Removes all known entries to simulate an empty address book.
    fileprivate func clearEntries() {
        receivingEntries.removeAll()
        changeEntries.removeAll()
        addressToEntry.removeAll()
    }
}
