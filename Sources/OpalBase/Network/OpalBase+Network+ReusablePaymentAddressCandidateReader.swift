// OpalBase+Network+ReusablePaymentAddressCandidateReader.swift

import Foundation

extension _OpalBase.Network {
    public struct ReusablePaymentAddressCandidateReader: Sendable {
        private let performFetchCandidateTransactions: @Sendable (
            OpalBase.ReusablePaymentAddress.InputHashPrefix,
            Int
        ) async throws -> [OpalBase.ReusablePaymentAddress.CandidateTransaction]

        public init(
            fetchCandidateTransactions: @escaping @Sendable (
                OpalBase.ReusablePaymentAddress.InputHashPrefix,
                Int
            ) async throws -> [OpalBase.ReusablePaymentAddress.CandidateTransaction]
        ) {
            self.performFetchCandidateTransactions = fetchCandidateTransactions
        }

        init(_ reader: any OpalBase.Network.ReusablePaymentAddressCandidateReadableClient) {
            self.init(fetchCandidateTransactions: reader.fetchCandidateTransactions(matching:sinceBlockHeight:))
        }

        public func fetchCandidateTransactions(
            matching prefix: OpalBase.ReusablePaymentAddress.InputHashPrefix,
            sinceBlockHeight: Int
        ) async throws -> [OpalBase.ReusablePaymentAddress.CandidateTransaction] {
            guard sinceBlockHeight >= 0 else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidBlockHeight(sinceBlockHeight)
            }
            return try await performFetchCandidateTransactions(prefix, sinceBlockHeight)
        }
    }
}

extension _OpalBase.Network.ReusablePaymentAddressCandidateReader: OpalBase.Network.ReusablePaymentAddressCandidateReadableClient {}
