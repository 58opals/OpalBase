import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumClient.Failover", .tags(.network))
struct NetworkFulcrumClientFailoverTests {
    private static let unhealthyServerAddresses: [URL] = [
        URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    ]
    private static let healthyServerAddresses: [URL] = [
        URL(string: "wss://bch.imaginary.cash:50004")!,
        URL(string: "wss://electrum.imaginary.cash:50004")!,
        URL(string: "wss://bch.loping.net:50004")!
    ]
    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    @Test("recovers unary request after unhealthy server failover", .timeLimit(.minutes(1)))
    func testUnaryRequestSucceedsAfterFailover() async throws {
        let configuration = Network.Configuration(
            serverURLs: Self.unhealthyServerAddresses + Self.healthyServerAddresses,
            connectionTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 6,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(12),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            try await client.reconnect()
            
            let tip: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
            
            let balance: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance = try await client.request(
                method: .blockchain(
                    .address(
                        .getBalance(address: Self.sampleCashAddress, tokenFilter: nil)
                    )
                )
            )
            #expect(balance.confirmed >= 0)
            #expect(balance.unconfirmed >= 0)
        }
    }
    
    @Test("skips an unhealthy bootstrap server and fulfils requests", .timeLimit(.minutes(1)))
    func testRequestSucceedsAfterFailover() async throws {
        let configuration = Network.Configuration(
            serverURLs: Self.unhealthyServerAddresses + Self.healthyServerAddresses,
            connectionTimeout: .seconds(10),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 6,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(12),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let tip: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
            
            let balance: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance = try await client.request(
                method: .blockchain(
                    .address(
                        .getBalance(address: Self.sampleCashAddress, tokenFilter: nil)
                    )
                ),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance.self
            )
            #expect(balance.confirmed >= 0)
            #expect(balance.unconfirmed >= 0)
            
            try await client.reconnect()
            
            let history: SwiftFulcrum.Response.Result.Blockchain.Address.GetHistory = try await client.request(
                method: .blockchain(
                    .address(
                        .getHistory(
                            address: Self.sampleCashAddress,
                            fromHeight: nil,
                            toHeight: nil,
                            includeUnconfirmed: true
                        )
                    )
                ),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Address.GetHistory.self
            )
            #expect(!history.transactions.isEmpty)
        }
    }
    
    @Test("performs requests after failing over from an unhealthy server", .timeLimit(.minutes(1)))
    func testClientRequestsSurviveInitialServerFailure() async throws {
        let configuration = Network.Configuration(
            serverURLs: Self.unhealthyServerAddresses + Self.healthyServerAddresses,
            connectionTimeout: .seconds(8),
            maximumMessageSize: 32 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 4,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(8),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let balance: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance = try await client.request(
                method: .blockchain(
                    .address(
                        .getBalance(address: Self.sampleCashAddress, tokenFilter: nil)
                    )
                )
            )
            
            #expect(balance.confirmed >= 0)
            #expect(balance.unconfirmed >= 0)
            
            let history: SwiftFulcrum.Response.Result.Blockchain.Address.GetHistory = try await client.request(
                method: .blockchain(
                    .address(
                        .getHistory(
                            address: Self.sampleCashAddress,
                            fromHeight: nil,
                            toHeight: nil,
                            includeUnconfirmed: true
                        )
                    )
                )
            )
            
            #expect(!history.transactions.isEmpty)
        }
    }
}
