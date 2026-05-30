// OpalBase+Network+Fulcrum+MempoolClient.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    protocol MempoolClient: Sendable {
        func fetchMempoolInfo(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Mempool.Info
        func fetchMempoolFeeHistogram(
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Mempool.FeeHistogram
    }
}

extension _OpalBase.Network.Fulcrum.Client: _OpalBase.Network.Fulcrum.MempoolClient {
    func fetchMempoolInfo(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Mempool.Info {
        try await request(
            SwiftFulcrum.API.mempool.info,
            options: options
        )
    }

    func fetchMempoolFeeHistogram(
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Mempool.FeeHistogram {
        try await request(
            SwiftFulcrum.API.mempool.feeHistogram,
            options: options
        )
    }
}
