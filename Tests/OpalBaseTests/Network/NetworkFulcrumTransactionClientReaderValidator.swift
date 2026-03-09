// NetworkFulcrumTransactionClientReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.TransactionClientReader", .tags(.network))
struct NetworkFulcrumTransactionClientReaderValidator {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let faultyServerAddress = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    private static let invalidServerAddress = URL(string: "not a url")!
    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let invalidCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
    private static let unknownTransactionIdentifier = String(repeating: "0", count: 64)
    private static let invalidRawTransaction = "00"

    @Test("fetches confirmation count consistent with live tip", .timeLimit(.minutes(1)))
    func fetchConfirmationsMatchesTipHeight() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let handler = OpalBase.Network.Fulcrum.TransactionClient(client: client)
            let history: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.GetHistory = try await client.request(
                method: .blockchain(
                    .address(
                        .getHistory(
                            address: Self.sampleCashAddress,
                            fromHeight: nil,
                            toHeight: nil,
                            shouldIncludeUnconfirmed: true
                        )
                    )
                )
            )

            let confirmedEntry = history.transactions.first { $0.height > 0 }
            #expect(confirmedEntry != nil)
            guard let confirmedEntry else {
                return
            }

            let tip: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.GetTip.self
            )

            let confirmations = try await handler.fetchConfirmations(
                forTransactionIdentifier: confirmedEntry.transactionHash
            )

            let expectedConfirmations = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
                transactionHeight: UInt(confirmedEntry.height),
                tipHeight: tip.height
            )

            #expect(confirmations == expectedConfirmations)
            #expect(confirmations ?? 0 > 0)
        }
    }

    @Test("fetches confirmations matching direct height queries", .timeLimit(.minutes(1)))
    func fetchConfirmationsMatchesServerHeights() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let handler = OpalBase.Network.Fulcrum.TransactionClient(client: client)
            let addressReader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            let confirmedHistory = try await addressReader.fetchHistory(for: Self.sampleCashAddress, includeUnconfirmed: false)
            let confirmedEntry = try #require(confirmedHistory.first(where: { $0.blockHeight > 0 }))

            let transactionHeight: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetHeight = try await client.request(
                method: .blockchain(.transaction(.getHeight(transactionHash: confirmedEntry.transactionIdentifier))),
                responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetHeight.self
            )
            #expect(transactionHeight.height == confirmedEntry.blockHeight)

            let tipHeight: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.GetTip.self
            )

            let expectedConfirmations = OpalBase.Network.Fulcrum.TransactionClient.calculateConfirmationCount(
                transactionHeight: transactionHeight.height,
                tipHeight: tipHeight.height
            )

            let confirmations = try await handler.fetchConfirmations(forTransactionIdentifier: confirmedEntry.transactionIdentifier)
            #expect(confirmations == expectedConfirmations)
            let nonOptionalConfirmations = try #require(confirmations)
            #expect(nonOptionalConfirmations >= 1)
        }
    }

    @Test("propagates server errors for unknown transactions", .timeLimit(.minutes(1)))
    func fetchConfirmationsPropagatesServerErrors() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let handler = OpalBase.Network.Fulcrum.TransactionClient(client: client)
            var thrownError: Error?
            do {
                _ = try await handler.fetchConfirmations(forTransactionIdentifier: Self.unknownTransactionIdentifier)
            } catch {
                thrownError = error
            }

            let failure = try #require(thrownError as? OpalBase.Network.Error)
            guard case .server = failure.reason else {
                Issue.record("Expected a server failure but received \(failure.reason)")
                return
            }
            #expect(failure.message != nil)
        }
    }

    @Test("rejects invalid raw transactions", .timeLimit(.minutes(1)))
    func broadcastTransactionRejectsInvalidPayload() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let handler = OpalBase.Network.Fulcrum.TransactionClient(client: client)
            var thrownError: Error?
            do {
                _ = try await handler.broadcastTransaction(rawTransactionHexadecimal: Self.invalidRawTransaction)
            } catch {
                thrownError = error
            }

            let failure = try #require(thrownError as? OpalBase.Network.Error)
            guard case .server = failure.reason else {
                guard case .protocolViolation = failure.reason else {
                    Issue.record("Expected a server or protocol failure but received \(failure.reason)")
                    return
                }
                #expect(failure.message != nil)
                return
            }
            #expect(failure.message != nil)
        }
    }

    @Test("rejects malformed transaction broadcast", .timeLimit(.minutes(1)))
    func broadcastTransactionTranslatesServerError() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let handler = OpalBase.Network.Fulcrum.TransactionClient(client: client)
            do {
                _ = try await handler.broadcastTransaction(rawTransactionHexadecimal: "00")
                Issue.record("Broadcast should have failed for malformed payload")
            } catch let failure as OpalBase.Network.Error {
                #expect(failure.message != nil)
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }
}
