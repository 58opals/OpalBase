// NetworkFulcrumMempoolReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.MempoolReader", .tags(.unit, .network))
struct NetworkFulcrumMempoolReaderValidator {
    @Test("maps mempool responses into OpalBase types")
    func fetchMempoolResponsesMapToOpalBaseTypes() async throws {
        let client = try MempoolClientTestActor(
            infoResponse: Self.makeInfoResponse(),
            histogramResponse: Self.makeHistogramResponse()
        )
        let reader = OpalBase.Network.Fulcrum.MempoolReader(client: client)

        let info = try await reader.fetchMempoolInfo()
        let histogram = try await reader.fetchFeeHistogram()

        #expect(info.mempoolMinimumFee == 0.00001)
        #expect(info.minimumRelayTransactionFee == 0.00002)
        #expect(info.incrementalRelayFee == 0.00003)
        #expect(info.unbroadcastCount == 7)
        #expect(info.isFullReplaceByFeeEnabled == true)
        #expect(histogram == [.init(fee: 1.5, virtualSize: 125), .init(fee: 3.0, virtualSize: 250)])
    }

    @Test("translates decoding failures for mempool requests")
    func fetchMempoolInfoTranslatesDecodingFailures() async throws {
        let client = MempoolClientTestActor(
            infoError: SwiftFulcrum.Client.Error.coding(.decode(nil))
        )
        let reader = OpalBase.Network.Fulcrum.MempoolReader(client: client)

        let failure = await Self.captureNetworkError {
            _ = try await reader.fetchMempoolInfo()
        }

        #expect(failure.reason == .decoding)
    }
    
    @Test("rejects invalid mempool info fee rates")
    func fetchMempoolInfoRejectsInvalidFeeRates() async throws {
        let client = try MempoolClientTestActor(
            infoResponse: Self.makeInfoResponse(mempoolMinimumFee: -1)
        )
        let reader = OpalBase.Network.Fulcrum.MempoolReader(client: client)
        
        let failure = await Self.captureNetworkError {
            _ = try await reader.fetchMempoolInfo()
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid mempool minimum fee: -1.0")
    }
    
    @Test("rejects invalid mempool info counts")
    func fetchMempoolInfoRejectsInvalidCounts() async throws {
        let client = try MempoolClientTestActor(
            infoResponse: Self.makeInfoResponse(unbroadcastCount: -1)
        )
        let reader = OpalBase.Network.Fulcrum.MempoolReader(client: client)
        
        let failure = await Self.captureNetworkError {
            _ = try await reader.fetchMempoolInfo()
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid unbroadcast count: -1")
    }
}

private actor MempoolClientTestActor: OpalBase.Network.Fulcrum.MempoolClient {
    private let infoResponse: SwiftFulcrum.Response.Mempool.GetInfo
    private let histogramResponse: SwiftFulcrum.Response.Mempool.GetFeeHistogram
    private let infoError: Swift.Error?

    init(
        infoResponse: SwiftFulcrum.Response.Mempool.GetInfo? = nil,
        histogramResponse: SwiftFulcrum.Response.Mempool.GetFeeHistogram? = nil,
        infoError: Swift.Error? = nil
    ) {
        self.infoResponse = infoResponse ?? (try! NetworkFulcrumMempoolReaderValidator.makeInfoResponse())
        self.histogramResponse = histogramResponse ?? (try! NetworkFulcrumMempoolReaderValidator.makeHistogramResponse())
        self.infoError = infoError
    }

    func fetchMempoolInfo(options _: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Mempool.GetInfo {
        if let infoError {
            throw infoError
        }
        return infoResponse
    }

    func fetchMempoolFeeHistogram(
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Mempool.GetFeeHistogram {
        histogramResponse
    }
}

private extension NetworkFulcrumMempoolReaderValidator {
    static func makeInfoResponse(
        mempoolMinimumFee: Double = 0.00001,
        minimumRelayTransactionFee: Double = 0.00002,
        incrementalRelayFee: Double = 0.00003,
        unbroadcastCount: Int = 7
    ) throws -> SwiftFulcrum.Response.Mempool.GetInfo {
        let payload = try JSONSerialization.data(withJSONObject: [
            "mempoolminfee": mempoolMinimumFee,
            "minrelaytxfee": minimumRelayTransactionFee,
            "incrementalrelayfee": incrementalRelayFee,
            "unbroadcastcount": unbroadcastCount,
            "fullrbf": true
        ])
        return try JSONDecoder().decode(SwiftFulcrum.Response.Mempool.GetInfo.self, from: payload)
    }

    static func makeHistogramResponse() throws -> SwiftFulcrum.Response.Mempool.GetFeeHistogram {
        let payload = try JSONSerialization.data(withJSONObject: [[3.0, 250], [1.5, 125]])
        return try JSONDecoder().decode(SwiftFulcrum.Response.Mempool.GetFeeHistogram.self, from: payload)
    }

    static func captureNetworkError(
        _ work: () async throws -> Void
    ) async -> OpalBase.Network.Error {
        do {
            try await work()
            Issue.record("Expected OpalBase.Network.Error")
            return .init(reason: .unknown)
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return .init(reason: .unknown, message: String(describing: error))
        }
    }
}
