// OpalBase+Network+ReusablePaymentAddressReader.swift

import Foundation

extension _OpalBase.Network {
    /// Transport-neutral access to Cash Code candidate transaction references.
    ///
    /// Confirmed queries use bounded half-open block-height ranges. Returned
    /// references remain candidates until their raw transactions are verified
    /// and matched locally.
    public struct ReusablePaymentAddressReader: Sendable {
        private let confirmedTransactionReferenceFetcher: @Sendable (
            OpalBase.ReusablePaymentAddress.FilterPrefix,
            Range<UInt>
        ) async throws -> [OpalBase.ReusablePaymentAddress.ConfirmedTransactionReference]
        private let mempoolTransactionReferenceFetcher: @Sendable (
            OpalBase.ReusablePaymentAddress.FilterPrefix
        ) async throws -> [OpalBase.ReusablePaymentAddress.MempoolTransactionReference]

        public init(
            fetchConfirmedTransactionReferences: @escaping @Sendable (
                OpalBase.ReusablePaymentAddress.FilterPrefix,
                Range<UInt>
            ) async throws -> [OpalBase.ReusablePaymentAddress.ConfirmedTransactionReference],
            fetchMempoolTransactionReferences: @escaping @Sendable (
                OpalBase.ReusablePaymentAddress.FilterPrefix
            ) async throws -> [OpalBase.ReusablePaymentAddress.MempoolTransactionReference]
        ) {
            self.confirmedTransactionReferenceFetcher =
                fetchConfirmedTransactionReferences
            self.mempoolTransactionReferenceFetcher =
                fetchMempoolTransactionReferences
        }

        public init(
            _ reader: OpalBase.Network.Fulcrum.ReusablePaymentAddressReader
        ) {
            self.init(
                fetchConfirmedTransactionReferences: { prefix, heights in
                    try await reader.fetchConfirmedTransactionReferences(
                        matching: prefix,
                        fromHeight: heights.lowerBound,
                        toHeight: heights.upperBound
                    )
                },
                fetchMempoolTransactionReferences: { prefix in
                    try await reader.fetchMempoolTransactionReferences(
                        matching: prefix
                    )
                }
            )
        }

        /// Fetches confirmed candidates in `heights`, interpreted as
        /// `[lowerBound, upperBound)`.
        public func fetchConfirmedTransactionReferences(
            matching filterPrefix: OpalBase.ReusablePaymentAddress.FilterPrefix,
            in heights: Range<UInt>
        ) async throws -> [OpalBase.ReusablePaymentAddress.ConfirmedTransactionReference] {
            guard !heights.isEmpty else { return [] }
            return try await confirmedTransactionReferenceFetcher(
                filterPrefix,
                heights
            )
        }

        /// Fetches the backend's current unconfirmed candidate snapshot.
        public func fetchMempoolTransactionReferences(
            matching filterPrefix: OpalBase.ReusablePaymentAddress.FilterPrefix
        ) async throws -> [OpalBase.ReusablePaymentAddress.MempoolTransactionReference] {
            try await mempoolTransactionReferenceFetcher(filterPrefix)
        }
    }
}
