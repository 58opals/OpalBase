// MempoolClientTestActor.swift

import Foundation
import SwiftFulcrum
@testable import OpalBase

actor MempoolClientTestActor: OpalBase.Network.Fulcrum.MempoolClient {
    private let infoResponse: SwiftFulcrum.Response.Mempool.Info
    private let histogramResponse: SwiftFulcrum.Response.Mempool.FeeHistogram
    private let infoError: Swift.Error?

    init(
        infoResponse: SwiftFulcrum.Response.Mempool.Info? = nil,
        histogramResponse: SwiftFulcrum.Response.Mempool.FeeHistogram? = nil,
        infoError: Swift.Error? = nil
    ) {
        self.infoResponse = infoResponse ?? (try! NetworkFulcrumMempoolReaderValidator.makeInfoResponse())
        self.histogramResponse = histogramResponse ?? (try! NetworkFulcrumMempoolReaderValidator.makeHistogramResponse())
        self.infoError = infoError
    }

    func fetchMempoolInfo(options _: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Mempool.Info {
        if let infoError {
            throw infoError
        }
        return infoResponse
    }

    func fetchMempoolFeeHistogram(
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Mempool.FeeHistogram {
        histogramResponse
    }
}
