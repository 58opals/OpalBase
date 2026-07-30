// OpalBase+Network+Fulcrum+ReusablePaymentAddressClient_.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    protocol ReusablePaymentAddressClient: Sendable {
        func fetchReusablePaymentAddressHistory(
            prefix: String,
            fromHeight: UInt,
            toHeight: UInt?,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Blockchain.RPA.History

        func fetchReusablePaymentAddressMempool(
            prefix: String,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Blockchain.RPA.Mempool
    }
}

extension _OpalBase.Network.Fulcrum.Client:
    _OpalBase.Network.Fulcrum.ReusablePaymentAddressClient
{
    func fetchReusablePaymentAddressHistory(
        prefix: String,
        fromHeight: UInt,
        toHeight: UInt?,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.RPA.History {
        try await request(
            SwiftFulcrum.API.blockchain.rpa.history(
                prefix: prefix,
                fromHeight: fromHeight,
                toHeight: toHeight
            ),
            options: options
        )
    }

    func fetchReusablePaymentAddressMempool(
        prefix: String,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.RPA.Mempool {
        try await request(
            SwiftFulcrum.API.blockchain.rpa.mempool(prefix: prefix),
            options: options
        )
    }
}
