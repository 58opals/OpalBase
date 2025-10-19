import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet Balance Monitoring Integration", .tags(.integration, .network, .fulcrum, .wallet))
struct WalletBalanceMonitoringIntegrationSuite {
    private static let mnemonicWords: [String] = [
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "about"
    ]

    private static func prepareAccount(using endpoint: String) async throws -> Account {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)

        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])

        return try await wallet.fetchAccount(at: 0)
    }

    @Test("streams live balance updates from Fulcrum", .tags(.slow))
    func streamsLiveBalanceUpdatesFromFulcrum() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }

        let account = try await Self.prepareAccount(using: endpoint)
        _ = try await account.calculateBalance()

        let balanceStream = try await account.monitorBalances()
        defer { Task { await account.stopBalanceMonitoring() } }

        enum Timeout: Swift.Error { case exceeded }

        let observedBalance = try await withThrowingTaskGroup(of: Satoshi.self) { group in
            group.addTask {
                var iterator = balanceStream.makeAsyncIterator()
                guard let next = try await iterator.next() else {
                    throw Timeout.exceeded
                }
                return next
            }

            group.addTask {
                try await Task.sleep(for: .seconds(20))
                throw Timeout.exceeded
            }

            guard let balance = try await group.next() else { throw Timeout.exceeded }
            group.cancelAll()
            return balance
        }

        let recalculated = try await account.calculateBalance()
        #expect(observedBalance == recalculated)
    }
}
