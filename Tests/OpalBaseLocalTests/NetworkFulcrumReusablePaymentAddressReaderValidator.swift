// NetworkFulcrumReusablePaymentAddressReaderValidator.swift

import Foundation
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite(
    "OpalBase.Network.Fulcrum.ReusablePaymentAddressReader",
    .tags(.unit, .network)
)
struct NetworkFulcrumReusablePaymentAddressReaderValidator {
    @Test("maps confirmed RPA candidate references without mixing mempool state")
    func mapsConfirmedCandidateReferences() async throws {
        let client = try Self.makeClient()
        let reader = OpalBase.Network.Fulcrum
            .ReusablePaymentAddressReader(client: client)
        let prefix = try ReusablePaymentAddressFixtureData
            .makeAddress()
            .filterPrefix

        let references = try await reader
            .fetchConfirmedTransactionReferences(
                matching: prefix,
                fromHeight: 812_000,
                toHeight: 812_060
            )

        let reference = try #require(references.first)
        #expect(references.count == 1)
        #expect(reference.blockHeight == 812_345)
        #expect(
            reference.transactionHash.reverseOrder.hexadecimalString
                == String(repeating: "a", count: 64)
        )
        let request = try #require(await client.readHistoryRequest())
        #expect(request.prefix == "5cbd")
        #expect(request.fromHeight == 812_000)
        #expect(request.toHeight == 812_060)
        #expect(request.timeout == .seconds(15))
    }

    @Test("maps mempool parent state and fees into a distinct reference type")
    func mapsMempoolParentStateAndFees() async throws {
        let client = try Self.makeClient()
        let reader = OpalBase.Network.Fulcrum
            .ReusablePaymentAddressReader(client: client)
        let prefix = try ReusablePaymentAddressFixtureData
            .makeAddress()
            .filterPrefix

        let references = try await reader
            .fetchMempoolTransactionReferences(matching: prefix)

        #expect(references.count == 2)
        #expect(references[0].fee == 1_234)
        #expect(references[0].hasUnconfirmedParent == false)
        #expect(references[1].fee == 5_678)
        #expect(references[1].hasUnconfirmedParent)
        #expect(
            references[1].transactionHash.reverseOrder.hexadecimalString
                == String(repeating: "c", count: 64)
        )
        let request = try #require(await client.readMempoolRequest())
        #expect(request.prefix == "5cbd")
        #expect(request.timeout == .seconds(8))
    }

    @Test("translates protocol failures without adding the filter prefix")
    func translatesProtocolFailuresWithoutAddingFilterPrefix() async throws {
        let client = try Self.makeClient(
            historyFailure: SwiftFulcrum.Client.Error.client(
                .protocolMismatch("RPA history response mismatch")
            )
        )
        let reader = OpalBase.Network.Fulcrum
            .ReusablePaymentAddressReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchConfirmedTransactionReferences(
                matching: ReusablePaymentAddressFixtureData
                    .makeAddress()
                    .filterPrefix,
                fromHeight: 812_000
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "RPA history response mismatch")
        Self.expectNoFilterPrefix(in: failure)
    }

    @Test("mempool failures do not expose the filter prefix")
    func mempoolFailuresDoNotExposeFilterPrefix() async throws {
        let client = try Self.makeClient(
            mempoolFailure: SwiftFulcrum.Client.Error.client(
                .protocolMismatch("RPA mempool response mismatch")
            )
        )
        let reader = OpalBase.Network.Fulcrum
            .ReusablePaymentAddressReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMempoolTransactionReferences(
                matching: ReusablePaymentAddressFixtureData
                    .makeAddress()
                    .filterPrefix
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "RPA mempool response mismatch")
        Self.expectNoFilterPrefix(in: failure)
    }

    @Test("preserves cancellation across the async reader boundary")
    func preservesCancellationAcrossAsyncReaderBoundary() async throws {
        let client = try Self.makeClient(
            mempoolFailure: CancellationError()
        )
        let reader = OpalBase.Network.Fulcrum
            .ReusablePaymentAddressReader(client: client)

        let failure = try await Self.captureNetworkError {
            _ = try await reader.fetchMempoolTransactionReferences(
                matching: ReusablePaymentAddressFixtureData
                    .makeAddress()
                    .filterPrefix
            )
        }

        #expect(failure.reason == .cancelled)
    }
}

private extension NetworkFulcrumReusablePaymentAddressReaderValidator {
    enum ErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    static func makeClient(
        historyFailure: (any Swift.Error & Sendable)? = nil,
        mempoolFailure: (any Swift.Error & Sendable)? = nil
    ) throws -> ReusablePaymentAddressClientTestActor {
        let history = try JSONDecoder().decode(
            SwiftFulcrum.Response.Blockchain.RPA.History.self,
            from: Data(
                """
                [
                  {
                    "height": 812345,
                    "tx_hash": "\(String(repeating: "a", count: 64))"
                  }
                ]
                """.utf8
            )
        )
        let mempool = try JSONDecoder().decode(
            SwiftFulcrum.Response.Blockchain.RPA.Mempool.self,
            from: Data(
                """
                [
                  {
                    "height": 0,
                    "tx_hash": "\(String(repeating: "b", count: 64))",
                    "fee": 1234
                  },
                  {
                    "height": -1,
                    "tx_hash": "\(String(repeating: "c", count: 64))",
                    "fee": 5678
                  }
                ]
                """.utf8
            )
        )
        return ReusablePaymentAddressClientTestActor(
            historyResponse: history,
            mempoolResponse: mempool,
            historyFailure: historyFailure,
            mempoolFailure: mempoolFailure
        )
    }

    static func captureNetworkError(
        operation: () async throws -> Void
    ) async throws -> OpalBase.Network.Error {
        do {
            try await operation()
            throw ErrorCaptureFailure.didNotThrow
        } catch let error as OpalBase.Network.Error {
            return error
        } catch {
            throw ErrorCaptureFailure.unexpected(error)
        }
    }

    static func expectNoFilterPrefix(
        in failure: OpalBase.Network.Error
    ) {
        let diagnosticText = [
            failure.message ?? "",
            failure.description,
        ] + failure.metadata.flatMap { key, value in
            [key, value]
        }
        #expect(
            diagnosticText.allSatisfy {
                $0.localizedCaseInsensitiveContains("5cbd") == false
            }
        )
    }
}
