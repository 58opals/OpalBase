// OpalBase+Network+Fulcrum+MempoolClient_.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    protocol MempoolClient: Sendable {
        func fetchMempoolInfo(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.RPC.Response.Result.Mempool.GetInfo
        func fetchMempoolFeeHistogram(
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.RPC.Response.Result.Mempool.GetFeeHistogram
    }
}

extension _OpalBase.Network.Fulcrum.Client: _OpalBase.Network.Fulcrum.MempoolClient {
    func fetchMempoolInfo(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.RPC.Response.Result.Mempool.GetInfo {
        try await request(
            method: .mempool(.getInfo),
            responseType: SwiftFulcrum.RPC.Response.Result.Mempool.GetInfo.self,
            options: options
        )
    }

    func fetchMempoolFeeHistogram(
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Mempool.GetFeeHistogram {
        try await request(
            method: .mempool(.getFeeHistogram),
            responseType: SwiftFulcrum.RPC.Response.Result.Mempool.GetFeeHistogram.self,
            options: options
        )
    }
}
