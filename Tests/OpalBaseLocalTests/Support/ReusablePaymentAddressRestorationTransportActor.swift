// ReusablePaymentAddressRestorationTransportActor.swift

import Foundation
@testable import OpalBase

actor ReusablePaymentAddressRestorationTransportActor {
    private var confirmedReferences: [
        OpalBase.ReusablePaymentAddress.ConfirmedTransactionReference
    ]
    private var mempoolReferences: [
        OpalBase.ReusablePaymentAddress.MempoolTransactionReference
    ]
    private var rawTransactions: [OpalBase.Transaction.Hash: Data]
    private let shouldFilterConfirmedReferences: Bool
    private var confirmedRanges: [Range<UInt>] = .init()
    private var rawTransactionRequests: [OpalBase.Transaction.Hash] = .init()

    private var shouldSuspendConfirmedRequest = false
    private var hasBegunSuspendedConfirmedRequest = false
    private var beganContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(
        confirmedReferences: [
            OpalBase.ReusablePaymentAddress.ConfirmedTransactionReference
        ] = .init(),
        mempoolReferences: [
            OpalBase.ReusablePaymentAddress.MempoolTransactionReference
        ] = .init(),
        rawTransactions: [OpalBase.Transaction.Hash: Data] = .init(),
        shouldFilterConfirmedReferences: Bool = true
    ) {
        self.confirmedReferences = confirmedReferences
        self.mempoolReferences = mempoolReferences
        self.rawTransactions = rawTransactions
        self.shouldFilterConfirmedReferences =
            shouldFilterConfirmedReferences
    }

    func fetchConfirmedTransactionReferences(
        matching _: OpalBase.ReusablePaymentAddress.FilterPrefix,
        in heights: Range<UInt>
    ) async throws -> [
        OpalBase.ReusablePaymentAddress.ConfirmedTransactionReference
    ] {
        confirmedRanges.append(heights)
        if shouldSuspendConfirmedRequest {
            shouldSuspendConfirmedRequest = false
            hasBegunSuspendedConfirmedRequest = true
            beganContinuation?.resume()
            beganContinuation = nil
            await withCheckedContinuation { continuation in
                resumeContinuation = continuation
            }
        }
        return shouldFilterConfirmedReferences
            ? confirmedReferences.filter {
                heights.contains($0.blockHeight)
            }
            : confirmedReferences
    }

    func fetchMempoolTransactionReferences(
        matching _: OpalBase.ReusablePaymentAddress.FilterPrefix
    ) -> [OpalBase.ReusablePaymentAddress.MempoolTransactionReference] {
        mempoolReferences
    }

    func fetchRawTransaction(
        for transactionHash: OpalBase.Transaction.Hash
    ) throws -> Data {
        rawTransactionRequests.append(transactionHash)
        guard let rawTransaction = rawTransactions[transactionHash] else {
            throw OpalBase.ReusablePaymentAddress.Error
                .transactionHashMismatch
        }
        return Data(rawTransaction)
    }

    func replaceConfirmedReferences(
        with references: [
            OpalBase.ReusablePaymentAddress.ConfirmedTransactionReference
        ]
    ) {
        confirmedReferences = references
    }

    func replaceMempoolReferences(
        with references: [
            OpalBase.ReusablePaymentAddress.MempoolTransactionReference
        ]
    ) {
        mempoolReferences = references
    }

    func storeRawTransaction(
        _ transaction: Data,
        for hash: OpalBase.Transaction.Hash
    ) {
        rawTransactions[hash] = Data(transaction)
    }

    func suspendNextConfirmedRequest() {
        shouldSuspendConfirmedRequest = true
        hasBegunSuspendedConfirmedRequest = false
    }

    func waitForSuspendedConfirmedRequest() async {
        guard !hasBegunSuspendedConfirmedRequest else { return }
        await withCheckedContinuation { continuation in
            beganContinuation = continuation
        }
    }

    func resumeConfirmedRequest() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func readConfirmedRanges() -> [Range<UInt>] {
        confirmedRanges
    }

    func readRawTransactionRequestCount(
        for hash: OpalBase.Transaction.Hash
    ) -> Int {
        rawTransactionRequests.count { $0 == hash }
    }
}
