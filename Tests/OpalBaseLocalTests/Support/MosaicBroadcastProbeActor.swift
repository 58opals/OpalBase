// MosaicBroadcastProbeActor.swift

#if os(macOS)
import Foundation
@testable import OpalBase

actor MosaicBroadcastProbeActor {
    private let journalProbe: MosaicAttemptJournalProbeActor
    private var failuresRemaining: Int
    private var broadcasts: [String] = []
    private var acceptedTransactionData: Data?
    private let presenceTransactionDataOverride: Data?
    private var observedPersistedIntent = false

    init(
        journalProbe: MosaicAttemptJournalProbeActor,
        failuresRemaining: Int = 0,
        presenceTransactionDataOverride: Data? = nil
    ) {
        self.journalProbe = journalProbe
        self.failuresRemaining = failuresRemaining
        self.presenceTransactionDataOverride = presenceTransactionDataOverride
    }

    nonisolated func makeClient(
        testingNetwork network: OpalBase.Network.Environment
    ) -> OpalBase.Account.MosaicNetworkAttestedTransactionClient {
        let client = OpalBase.Network.TransactionClient(
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
        return .init(
            testingNetwork: network,
            transactionClient: client,
            fetchFreshDetailedTransaction: { hash in
                try await self.fetchFreshDetailedTransaction(for: hash)
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
        acceptedTransactionData = data
        return OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(data)
        ).reverseOrder.hexadecimalString
    }

    private func fetchFreshDetailedTransaction(
        for hash: OpalBase.Transaction.Hash
    ) throws -> OpalBase.Transaction.Detail {
        if let presenceTransactionDataOverride {
            let decoded = try OpalBase.Transaction.decode(
                from: presenceTransactionDataOverride
            )
            guard let size = UInt32(
                exactly: presenceTransactionDataOverride.count
            ) else {
                throw MosaicBroadcastProbeFailure.scripted
            }
            return .init(
                transaction: decoded.transaction,
                blockHash: nil,
                blockTime: nil,
                confirmations: nil,
                hash: hash,
                rawTransactionData: presenceTransactionDataOverride,
                size: size,
                time: nil
            )
        }
        guard let acceptedTransactionData else {
            throw OpalBase.Network.Error(
                reason: .server(code: -5),
                message: "missing transaction"
            )
        }
        let expectedHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(acceptedTransactionData)
        )
        guard hash == expectedHash else {
            throw OpalBase.Network.Error(
                reason: .protocolViolation,
                message: "transaction hash mismatch"
            )
        }
        let decoded = try OpalBase.Transaction.decode(
            from: acceptedTransactionData
        )
        guard let size = UInt32(exactly: acceptedTransactionData.count) else {
            throw MosaicBroadcastProbeFailure.scripted
        }
        return .init(
            transaction: decoded.transaction,
            blockHash: nil,
            blockTime: nil,
            confirmations: nil,
            hash: expectedHash,
            rawTransactionData: acceptedTransactionData,
            size: size,
            time: nil
        )
    }
}
#endif
