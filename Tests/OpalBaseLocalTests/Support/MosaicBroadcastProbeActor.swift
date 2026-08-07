// MosaicBroadcastProbeActor.swift

#if os(macOS)
import Foundation
@testable import OpalBase

actor MosaicBroadcastProbeActor {
    private let journalProbe: MosaicAttemptJournalProbeActor
    private var failuresRemaining: Int
    private var broadcasts: [String] = []
    private var observedPersistedIntent = false

    init(
        journalProbe: MosaicAttemptJournalProbeActor,
        failuresRemaining: Int = 0
    ) {
        self.journalProbe = journalProbe
        self.failuresRemaining = failuresRemaining
    }

    nonisolated func makeClient() -> OpalBase.Network.TransactionClient {
        .init(
            broadcastTransaction: { rawTransaction in
                try await self.broadcast(rawTransaction)
            },
            fetchConfirmations: { _ in nil },
            fetchConfirmationStatus: { transactionHash in
                .init(
                    transactionHash: transactionHash,
                    transactionHeight: nil,
                    tipHeight: 0,
                    confirmations: nil
                )
            }
        )
    }

    func readBroadcasts() -> [String] {
        broadcasts
    }

    func readObservedPersistedIntent() -> Bool {
        observedPersistedIntent
    }

    private func broadcast(_ rawTransaction: String) async throws -> String {
        let records = await journalProbe.readRecords()
        if case .broadcastIntent? = records.last {
            observedPersistedIntent = true
        }
        broadcasts.append(rawTransaction)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw MosaicBroadcastProbeFailure.scripted
        }
        let data = try Data(hexadecimalString: rawTransaction)
        return OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(data)
        ).reverseOrder.hexadecimalString
    }
}
#endif
