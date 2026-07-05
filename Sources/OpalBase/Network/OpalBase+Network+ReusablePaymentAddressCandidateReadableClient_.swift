// OpalBase+Network+ReusablePaymentAddressCandidateReadableClient_.swift

import Foundation

extension _OpalBase.Network {
    protocol ReusablePaymentAddressCandidateReadableClient: Sendable {
        func fetchCandidateTransactions(
            matching prefix: OpalBase.ReusablePaymentAddress.InputHashPrefix,
            sinceBlockHeight: Int
        ) async throws -> [OpalBase.ReusablePaymentAddress.CandidateTransaction]
    }
}
