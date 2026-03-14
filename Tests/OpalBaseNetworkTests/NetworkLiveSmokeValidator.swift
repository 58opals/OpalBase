// NetworkLiveSmokeValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network live smoke", .tags(.integration, .network))
struct NetworkLiveSmokeValidator {
    private static let fallbackServers: [URL] = [
        URL(string: "wss://bch.imaginary.cash:50004")!,
        URL(string: "wss://bch.loping.net:50004")!
    ]

    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"

    @Test("connects and reads current tip", .timeLimit(.minutes(1)))
    func connectAndFetchTip() async throws {
        guard NetworkTestClient.isLiveNetworkEnabled else { return }
        let configuration = makeSmokeConfiguration()

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.BlockHeaderReader(client: client)
            let tip = try await reader.fetchTip()
            #expect(tip.height > 0)
            #expect(!tip.headerHexadecimal.isEmpty)
        }
    }

    @Test("fetches an address balance from a live server", .timeLimit(.minutes(1)))
    func fetchLiveAddressBalance() async throws {
        guard NetworkTestClient.isLiveNetworkEnabled else { return }
        let configuration = makeSmokeConfiguration()

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            let balance = try await reader.fetchBalance(for: Self.sampleCashAddress, tokenFilter: .include)
            #expect(balance.confirmed >= 0)
            #expect(balance.unconfirmed >= 0)
        }
    }
}

private extension NetworkLiveSmokeValidator {
    func makeSmokeConfiguration() -> OpalBase.Network.Configuration {
        let envServer = ProcessInfo.processInfo.environment["OPAL_FULCRUM_URL"].flatMap(URL.init(string:))
        let servers = [envServer].compactMap { $0 } + Self.fallbackServers
        return OpalBase.Network.Configuration(
            serverURLs: servers,
            connectionTimeout: .seconds(10),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 2,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(8),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )
    }
}
