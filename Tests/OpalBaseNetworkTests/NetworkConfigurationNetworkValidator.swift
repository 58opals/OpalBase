// NetworkConfigurationNetworkValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Configuration (OpalBase.Network)", .tags(.integration, .network))
struct NetworkConfigurationNetworkValidator {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50004")!
    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"

    @Test("connects to a live Fulcrum server", .timeLimit(.minutes(1)))
    func connectionToFulcrumServer() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [
                URL(string: "wss://bch.imaginary.cash:50004")!,
                URL(string: "wss://bch.loping.net:50004")!
            ],
            connectTimeout: .seconds(15),
            maximumMessageSize: 32 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 3,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(5),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let headerReader = OpalBase.Network.Fulcrum.BlockHeaderReader(client: client)
            let tip = try await headerReader.fetchTip()

            #expect(tip.height > 0)
            #expect(!tip.headerHexadecimal.isEmpty)
        }
    }

    @Test("connects to fulcrum using wallet-centric configuration", .timeLimit(.minutes(1)))
    func connectFulcrumWithCustomConfiguration() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectTimeout: .seconds(8),
            maximumMessageSize: 8 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 2,
                initialDelay: .seconds(0.5),
                maximumDelay: .seconds(4),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let addressReader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            let balance = try await addressReader.fetchBalance(for: Self.sampleCashAddress, tokenFilter: .include)
            #expect(balance.confirmed >= 0)

            try await client.reconnect()

            let history = try await addressReader.fetchHistory(for: Self.sampleCashAddress, includeUnconfirmed: true)
            #expect(!history.isEmpty)
        }
    }

    @Test("connects with bundled bootstrap when server list is empty", .timeLimit(.minutes(1)))
    func connectFulcrumUsingBundledBootstrapServers() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: .init())

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let headerReader = OpalBase.Network.Fulcrum.BlockHeaderReader(client: client)
            let tip = try await headerReader.fetchTip()

            #expect(tip.height > 0)
            #expect(!tip.headerHexadecimal.isEmpty)
        }
    }

    @Test("remains usable after idling past connect timeout", .timeLimit(.minutes(1)))
    func remainUsableAfterIdlingPastConnectTimeout() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectTimeout: .seconds(2),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 2,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(6),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            try await Task.sleep(for: .seconds(4))

            let tip: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Headers.GetTip.self,
                options: .init(timeout: .seconds(15))
            )

            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
        }
    }
}
