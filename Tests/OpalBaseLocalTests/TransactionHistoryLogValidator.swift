// TransactionHistoryLogValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Address.Book.TransactionLog", .tags(.unit, .wallet))
struct TransactionHistoryLogValidator {
    @Test("store removes stale script hash indexes when replacing a record")
    func storeRemovesStaleScriptHashIndexesWhenReplacingRecord() {
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x24, count: 32))
        let oldScriptHash = String(repeating: "e", count: 64)
        let secondOldScriptHash = String(repeating: "0", count: 64)
        let newScriptHash = String(repeating: "f", count: 64)
        let timestamp = Date(timeIntervalSince1970: 1)
        var log = OpalBase.Address.Book.TransactionLog()
        var oldRecord = Self.makeRecord(
            transactionHash: transactionHash,
            scriptHash: oldScriptHash,
            timestamp: timestamp
        )
        oldRecord.chainMetadata.scriptHashes.insert(secondOldScriptHash)
        let newRecord = Self.makeRecord(
            transactionHash: transactionHash,
            scriptHash: newScriptHash,
            timestamp: timestamp
        )

        log.store(oldRecord)
        log.store(newRecord)
        let staleChangeSet = log.replaceHistory(
            for: oldScriptHash,
            entries: [],
            tokenDeltasByHash: [:],
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let secondStaleChangeSet = log.replaceHistory(
            for: secondOldScriptHash,
            entries: [],
            tokenDeltasByHash: [:],
            timestamp: Date(timeIntervalSince1970: 3)
        )

        #expect(staleChangeSet.isEmpty)
        #expect(secondStaleChangeSet.isEmpty)
        #expect(log.loadRecord(for: transactionHash)?.chainMetadata.scriptHashes == [newScriptHash])
    }

    private static func makeRecord(
        transactionHash: OpalBase.Transaction.Hash,
        scriptHash: String,
        timestamp: Date
    ) -> OpalBase.Transaction.History.Record {
        OpalBase.Transaction.History.Record.makeRecord(
            for: .init(transactionHash: transactionHash, height: -1, fee: nil),
            scriptHash: scriptHash,
            timestamp: timestamp
        )
    }
}
