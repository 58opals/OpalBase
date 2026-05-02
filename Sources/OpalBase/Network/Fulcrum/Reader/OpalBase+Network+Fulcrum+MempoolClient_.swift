// OpalBase+Network+Fulcrum+MempoolClient_.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    protocol MempoolClient: Sendable {
        func fetchMempoolInfo(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Mempool.GetInfo
        func fetchMempoolFeeHistogram(
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Mempool.GetFeeHistogram
    }
}

extension _OpalBase.Network.Fulcrum.Client: _OpalBase.Network.Fulcrum.MempoolClient {
    func fetchMempoolInfo(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Mempool.GetInfo {
        try await request(
            .mempool.getInfo,
            options: options
        )
    }

    func fetchMempoolFeeHistogram(
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Mempool.GetFeeHistogram {
        try await request(
            .mempool.getFeeHistogram,
            options: options
        )
    }
}
