// MosaicAttemptJournalProbeActor.swift

#if os(macOS)
@testable import OpalBase

enum MosaicAttemptJournalProbeFailure: Swift.Error {
    case scripted
}

actor MosaicAttemptJournalProbeActor {
    private var records: [OpalBase.Account.MosaicAttemptJournal.Record] = []
    private var appendAttemptIndex = 0
    private var failingAppendIndices: Set<Int>

    init(failingAppendIndices: Set<Int> = []) {
        self.failingAppendIndices = failingAppendIndices
    }

    nonisolated func makeJournal() -> OpalBase.Account.MosaicAttemptJournal {
        .init { record in
            try await self.append(record)
        }
    }

    func readRecords() -> [OpalBase.Account.MosaicAttemptJournal.Record] {
        records
    }

    private func append(
        _ record: OpalBase.Account.MosaicAttemptJournal.Record
    ) throws {
        let index = appendAttemptIndex
        appendAttemptIndex += 1
        if failingAppendIndices.remove(index) != nil {
            throw MosaicAttemptJournalProbeFailure.scripted
        }
        records.append(record)
    }
}
#endif
