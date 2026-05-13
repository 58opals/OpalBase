// NetworkFulcrumTransactionClientReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.TransactionClientReader", .tags(.integration, .network))
struct NetworkFulcrumTransactionClientReaderValidator {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50004")!
    private static let faultyServerAddress = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    private static let invalidServerAddress = URL(string: "not a url")!
    private static let sampleCashAddr = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let invalidCashAddr = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
    private static let unknownTransactionIdentifier = String(repeating: "0", count: 64)
    private static let invalidRawTransaction = "00"

    @Test("fetches confirmation count consistent with live tip", .timeLimit(.minutes(1)))
    func fetchConfirmationsMatchesTipHeight() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let handler = OpalBase.Network.Fulcrum.TransactionClient(client: client)
            let history: SwiftFulcrum.Response.Blockchain.Address.GetHistory = try await client.request(
                .blockchain.address.getHistory(
                    address: Self.sampleCashAddr,
                    shouldIncludeUnconfirmed: true
                )
            )

            let confirmedEntry = history.transactions.first { $0.height > 0 }
            #expect(confirmedEntry != nil)
            guard let confirmedEntry else {
                return
            }

            let tip: SwiftFulcrum.Response.Blockchain.Headers.GetTip = try await client.request(
                .blockchain.headers.getTip
            )

            let confirmations = try await handler.fetchConfirmations(
                forTransactionIdentifier: confirmedEntry.transactionHash
            )

            let transactionHash = try OpalBase.Network.decodeTransactionHash(from: confirmedEntry.transactionHash)
            let expectedConfirmations = try OpalBase.Network.Fulcrum.TransactionClient.makeConfirmationStatus(
                transactionHash: transactionHash,
                transactionHeight: UInt(confirmedEntry.height),
                tipHeight: tip.height
            ).confirmations

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
            let confirmedHistory = try await addressReader.fetchHistory(for: Self.sampleCashAddr, includeUnconfirmed: false)
            let confirmedEntry = try #require(confirmedHistory.first(where: { $0.blockHeight > 0 }))

            let transactionHeight: SwiftFulcrum.Response.Blockchain.Transaction.GetHeight = try await client.request(
                .blockchain.transaction.getHeight(transactionHash: confirmedEntry.transactionIdentifier)
            )
            let resolvedTransactionHeight = try #require(transactionHeight.height)
            #expect(resolvedTransactionHeight == confirmedEntry.blockHeight)

            let tipHeight: SwiftFulcrum.Response.Blockchain.Headers.GetTip = try await client.request(
                .blockchain.headers.getTip
            )

            let transactionHash = try OpalBase.Network.decodeTransactionHash(from: confirmedEntry.transactionIdentifier)
            let expectedConfirmations = try OpalBase.Network.Fulcrum.TransactionClient.makeConfirmationStatus(
                transactionHash: transactionHash,
                transactionHeight: UInt(resolvedTransactionHeight),
                tipHeight: tipHeight.height
            ).confirmations

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
