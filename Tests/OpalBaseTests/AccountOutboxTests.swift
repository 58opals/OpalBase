import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Outbox Tests")
struct OutboxTests {
    let folder: URL
    let outbox: Account.Outbox

    init() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        outbox = try Account.Outbox(folderURL: folder)
    }
}

extension OutboxTests {
    @Test mutating func testPersistenceOnFailureAndPurge() async throws {
        let tx = Data([0xde, 0xad, 0xbe, 0xef])
        try await outbox.save(transactionData: tx)
        #expect((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.count == 1, "Transaction should be stored")

        let badFulcrum = try await Fulcrum(url: "wss://invalid.example.com")
        await outbox.retryPendingTransactions(using: Adapter.SwiftFulcrum.GatewayClient(fulcrum: badFulcrum))
        #expect((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.count == 1, "Failed retry should keep file")

        await outbox.purgeTransactions()
        #expect((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.isEmpty ?? false, "Purge should clear files")
    }
}

@Suite("Account Outbox API Tests")
struct AccountOutboxAPITests {
    let folder: URL
    var account: Account

    init() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = try PrivateKey.Extended.Root(seed: Data([0x00]))
        let rootKey = PrivateKey.Extended(rootKey: root)
        account = try await Account(fulcrumServerURLs: ["wss://invalid.example.com"],
                                    rootExtendedPrivateKey: rootKey,
                                    purpose: .bip44,
                                    coinType: .bitcoinCash,
                                    account: try .init(rawIndexInteger: 0),
                                    outboxPath: folder)
    }
}

extension AccountOutboxAPITests {
    @Test mutating func testRetryAndPurgeViaAccount() async throws {
        let tx = Data([0xca, 0xfe])
        try await account.outbox.save(transactionData: tx)

        await account.retryOutbox()
        #expect((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.count == 1, "Failed retry should keep file")

        await account.purgeOutbox()
        #expect((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.isEmpty ?? false, "Purge should clear files")
    }
}
