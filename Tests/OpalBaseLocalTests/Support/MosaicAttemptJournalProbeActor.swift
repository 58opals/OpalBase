// MosaicAttemptJournalProbeActor.swift

#if os(macOS)
@testable import OpalBase

actor MosaicAttemptJournalProbeActor {
    private var records: [OpalBase.Account.MosaicAttemptJournal.Record] = []
    private var appendAttemptIndex = 0
    private var failingAppendIndices: Set<Int>
    private let suspendedAppendIndex: Int?
    private let suspensionProbe: MosaicOperationSuspensionProbeActor?
    private let cancellationSensitiveAppendIndices: Set<Int>
    private var cancellationObservations: [Int: Bool] = [:]
    private var cancellationObservationWaiters: [
        Int: [CheckedContinuation<Bool, Never>]
    ] = [:]

    init(
        failingAppendIndices: Set<Int> = [],
        suspendedAppendIndex: Int? = nil,
        suspensionProbe: MosaicOperationSuspensionProbeActor? = nil,
        cancellationSensitiveAppendIndices: Set<Int> = []
    ) {
        self.failingAppendIndices = failingAppendIndices
        self.suspendedAppendIndex = suspendedAppendIndex
        self.suspensionProbe = suspensionProbe
        self.cancellationSensitiveAppendIndices = cancellationSensitiveAppendIndices
    }

    nonisolated func makeJournal() -> OpalBase.Account.MosaicAttemptJournal {
        .init { record in
            try await self.append(record)
        }
    }

    func readRecords() -> [OpalBase.Account.MosaicAttemptJournal.Record] {
        records
    }

    func waitForCancellationObservation(atAppendIndex index: Int) async -> Bool {
        if let observation = cancellationObservations[index] {
            return observation
        }
        return await withCheckedContinuation { continuation in
            cancellationObservationWaiters[index, default: []].append(continuation)
        }
    }

    private func append(
        _ record: OpalBase.Account.MosaicAttemptJournal.Record
    ) async throws {
        let index = appendAttemptIndex
        appendAttemptIndex += 1
        if index == suspendedAppendIndex, let suspensionProbe {
            await suspensionProbe.suspend()
        }
        let wasCancelled = Task.isCancelled
        cancellationObservations[index] = wasCancelled
        cancellationObservationWaiters.removeValue(forKey: index)?.forEach {
            $0.resume(returning: wasCancelled)
        }
        if cancellationSensitiveAppendIndices.contains(index) {
            try Task.checkCancellation()
        }
        if failingAppendIndices.remove(index) != nil {
            throw MosaicAttemptJournalProbeFailure.scripted
        }
        records.append(record)
    }
}
#endif
