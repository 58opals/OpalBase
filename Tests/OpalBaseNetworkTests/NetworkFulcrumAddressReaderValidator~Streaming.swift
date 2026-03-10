// NetworkFulcrumAddressReaderValidator~Streaming.swift

import Foundation
import Testing
@testable import OpalBase

extension NetworkFulcrumAddressReaderValidator {
    @Test("lists token-bearing outputs with parsed token data", .timeLimit(.minutes(1)))
    func fetchTokenUnspentOutputsIncludesTokenData() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            let tokenOutputs = try await reader.fetchUnspentOutputs(for: Self.tokenCashAddress, tokenFilter: .only)

            #expect(!tokenOutputs.isEmpty)
            #expect(tokenOutputs.allSatisfy { $0.tokenData != nil })
        }
    }

    @Test("subscribes to address updates and cancels cleanly", .timeLimit(.minutes(1)))
    func subscribeToAddressDeliversInitialSnapshot() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            let stream = try await reader.subscribeToAddress(Self.sampleCashAddress)
            var iterator = stream.makeAsyncIterator()

            let initialUpdate = try await iterator.next()
            #expect(initialUpdate?.kind == .initialSnapshot)
            #expect(initialUpdate?.address == Self.sampleCashAddress)
            #expect(!(initialUpdate?.status?.isEmpty ?? true))

            let pendingChange = Task { try await iterator.next() }
            try await Task.sleep(nanoseconds: 200_000_000)
            pendingChange.cancel()

            do {
                _ = try await pendingChange.value
            } catch is CancellationError {
                // Expected when cancelling before a new update arrives.
            }
        }
    }
}

