// OpalBase+Network+Fulcrum+ReusablePaymentAddressReader.swift

import Foundation

extension _OpalBase.Network.Fulcrum {
    /// Reads confirmed and mempool candidate transaction references from an
    /// RPA-capable Fulcrum server.
    ///
    /// The reader keeps confirmed history and mempool state in distinct return
    /// types. A returned reference must still be fetched and passed through
    /// Cash Code matching before it can be treated as a payment.
    public struct ReusablePaymentAddressReader: Sendable {
        private let client: any ReusablePaymentAddressClient
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout

        public init(
            client: OpalBase.Network.Fulcrum.Client,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()
        ) {
            self.init(
                client: client as any ReusablePaymentAddressClient,
                timeouts: timeouts
            )
        }

        init(
            client: any ReusablePaymentAddressClient,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()
        ) {
            self.client = client
            self.timeouts = timeouts
        }

        /// Fetches confirmed candidate transaction references for an inclusive
        /// starting height and optional exclusive ending height.
        public func fetchConfirmedTransactionReferences(
            matching filterPrefix:
                OpalBase.ReusablePaymentAddress.FilterPrefix,
            fromHeight: UInt,
            toHeight: UInt? = nil
        ) async throws
            -> [OpalBase.ReusablePaymentAddress
                .ConfirmedTransactionReference]
        {
            try await OpalBase.Network.performWithFailureTranslation {
                let response = try await client
                    .fetchReusablePaymentAddressHistory(
                        prefix: filterPrefix.hexadecimalString,
                        fromHeight: fromHeight,
                        toHeight: toHeight,
                        options: .init(
                            timeout:
                                timeouts.reusablePaymentAddressHistory
                        )
                    )
                return try response.transactions.map { transaction in
                    let hash = try OpalBase.Network.decodeTransactionHash(
                        from: transaction.transactionHash,
                        label: "RPA history transaction hash"
                    )
                    return OpalBase.ReusablePaymentAddress
                        .ConfirmedTransactionReference(
                            transactionHash: hash,
                            blockHeight: transaction.height
                        )
                }
            }
        }

        /// Fetches unconfirmed candidate transaction references.
        public func fetchMempoolTransactionReferences(
            matching filterPrefix:
                OpalBase.ReusablePaymentAddress.FilterPrefix
        ) async throws
            -> [OpalBase.ReusablePaymentAddress
                .MempoolTransactionReference]
        {
            try await OpalBase.Network.performWithFailureTranslation {
                let response = try await client
                    .fetchReusablePaymentAddressMempool(
                        prefix: filterPrefix.hexadecimalString,
                        options: .init(
                            timeout:
                                timeouts.reusablePaymentAddressMempool
                        )
                    )
                return try response.transactions.map { transaction in
                    let hash = try OpalBase.Network.decodeTransactionHash(
                        from: transaction.transactionHash,
                        label: "RPA mempool transaction hash"
                    )
                    guard let fee = UInt64(exactly: transaction.fee) else {
                        throw OpalBase.Network.Error(
                            reason: .decoding,
                            message: "RPA mempool transaction fee overflow"
                        )
                    }
                    return OpalBase.ReusablePaymentAddress
                        .MempoolTransactionReference(
                            transactionHash: hash,
                            fee: fee,
                            hasUnconfirmedParent: transaction.height == -1
                        )
                }
            }
        }
    }
}
