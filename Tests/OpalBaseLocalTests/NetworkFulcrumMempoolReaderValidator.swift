// NetworkFulcrumMempoolReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.MempoolReader", .tags(.unit, .network))
struct NetworkFulcrumMempoolReaderValidator {
    @Test("maps mempool responses into OpalBase types")
    func mapMempoolResponsesToOpalBaseTypes() async throws {
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
        #expect(histogram == [.init(fee: 3.0, virtualSize: 250), .init(fee: 1.5, virtualSize: 125)])
    }

    @Test("translates decoding failures for mempool requests")
    func fetchMempoolInfoTranslatesDecodingFailures() async throws {
        let client = try MempoolClientTestActor(
            infoError: SwiftFulcrum.Client.Error.coding(.decode(nil))
        )
        let reader = OpalBase.Network.Fulcrum.MempoolReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMempoolInfo()
        }

        #expect(failure.reason == .decoding)
    }
    
    @Test(
        "rejects invalid mempool info fields",
        arguments: MempoolInfoFieldFixture.allCases
    )
    func rejectInvalidMempoolInfoFields(field: MempoolInfoFieldFixture) async throws {
        let infoError = try field.makeInfoDecodeFailure()

        let client = try MempoolClientTestActor(infoError: infoError)
        let reader = OpalBase.Network.Fulcrum.MempoolReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMempoolInfo()
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == field.expectedMessage)
    }

    @Test("rejects invalid mempool fee histogram bins")
    func rejectInvalidMempoolFeeHistogramBins() async throws {
        let virtualSizeReader = OpalBase.Network.Fulcrum.MempoolReader(
            client: try MempoolClientTestActor(
                histogramResponse: Self.makeHistogramResponse(bins: [[1.0, 0]])
            )
        )

        let virtualSizeFailure = try await Self.captureNetworkError {
            _ = try await virtualSizeReader.fetchFeeHistogram()
        }

        #expect(virtualSizeFailure.reason == .decoding)
        #expect(virtualSizeFailure.message == "Invalid mempool fee histogram virtual size: 0")

        let zeroFeeReader = OpalBase.Network.Fulcrum.MempoolReader(
            client: try MempoolClientTestActor(
                histogramResponse: Self.makeHistogramResponse(bins: [[0.0, 1]])
            )
        )

        let zeroFeeHistogram = try await zeroFeeReader.fetchFeeHistogram()
        #expect(zeroFeeHistogram == [.init(fee: 0.0, virtualSize: 1)])
    }
}

extension NetworkFulcrumMempoolReaderValidator {
    enum MempoolInfoDecodeFailure: Swift.Error {
        case didNotThrow
    }

    enum MempoolInfoFieldFixture: CaseIterable, Sendable {
        case fee
        case count

        var expectedMessage: String {
            switch self {
            case .fee:
                return "Invalid mempool minimum fee: -1.0"
            case .count:
                return "Invalid unbroadcast count: -1"
            }
        }

        func makeInfoDecodeFailure() throws -> SwiftFulcrum.Client.Error {
            switch self {
            case .fee:
                return try NetworkFulcrumMempoolReaderValidator.makeInfoDecodeFailure(mempoolMinimumFee: -1)
            case .count:
                return try NetworkFulcrumMempoolReaderValidator.makeInfoDecodeFailure(unbroadcastCount: -1)
            }
        }
    }

    static func makeInfoResponse(
        mempoolMinimumFee: Double = 0.00001,
        minimumRelayTransactionFee: Double = 0.00002,
        incrementalRelayFee: Double = 0.00003,
        unbroadcastCount: Int = 7
    ) throws -> SwiftFulcrum.Response.Mempool.Info {
        let payload = try JSONSerialization.data(withJSONObject: [
            "mempoolminfee": mempoolMinimumFee,
            "minrelaytxfee": minimumRelayTransactionFee,
            "incrementalrelayfee": incrementalRelayFee,
            "unbroadcastcount": unbroadcastCount,
            "fullrbf": true
        ])
        return try JSONDecoder().decode(SwiftFulcrum.Response.Mempool.Info.self, from: payload)
    }

    static func makeInfoDecodeFailure(
        mempoolMinimumFee: Double = 0.00001,
        minimumRelayTransactionFee: Double = 0.00002,
        incrementalRelayFee: Double = 0.00003,
        unbroadcastCount: Int = 7
    ) throws -> SwiftFulcrum.Client.Error {
        do {
            _ = try makeInfoResponse(
                mempoolMinimumFee: mempoolMinimumFee,
                minimumRelayTransactionFee: minimumRelayTransactionFee,
                incrementalRelayFee: incrementalRelayFee,
                unbroadcastCount: unbroadcastCount
            )
        } catch {
            return SwiftFulcrum.Client.Error.coding(.decode(error))
        }
        throw MempoolInfoDecodeFailure.didNotThrow
    }

    static func makeHistogramResponse(
        bins: [[Any]] = [[3.0, 250], [1.5, 125]]
    ) throws -> SwiftFulcrum.Response.Mempool.FeeHistogram {
        let payload = try JSONSerialization.data(withJSONObject: bins)
        return try JSONDecoder().decode(SwiftFulcrum.Response.Mempool.FeeHistogram.self, from: payload)
    }

    static func captureNetworkError(
        _ work: () async throws -> Void
    ) async throws -> OpalBase.Network.Error {
        do {
            try await work()
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch {
            throw NetworkErrorCaptureFailure.unexpected(error)
        }
        throw NetworkErrorCaptureFailure.didNotThrow
    }

    enum NetworkErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }
}
