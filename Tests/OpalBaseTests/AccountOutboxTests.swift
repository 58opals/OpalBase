import Testing
import Foundation
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
        try await outbox.save(tx)
        #expect((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.count == 1, "Transaction should be stored")

        let badFulcrum = try Fulcrum(url: "wss://invalid.example.com")
        await outbox.retry(using: badFulcrum)
        #expect((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.count == 1, "Failed retry should keep file")

        await outbox.purge()
        #expect((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.isEmpty ?? false, "Purge should clear files")
    }
}
