import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumClient", .tags(.network))
struct NetworkFulcrumClientTests {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let faultyServerAddress = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    private static let invalidServerAddress = URL(string: "not a url")!
    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let invalidCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
    
    @Test("performs wallet-centric requests and reconnects", .timeLimit(.minutes(1)))
    func testWalletOperationsWithLiveFulcrum() async throws {
        let configuration = Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectionTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 4,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let storedConfiguration = await client.configuration
            #expect(storedConfiguration == configuration)
            
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
                )
            )
            #expect(!history.transactions.isEmpty)
        }
    }
    
    @Test("performs wallet critical unary calls and reconnects", .timeLimit(.minutes(1)))
    func testClientPerformsWalletCriticalRequests() async throws {
        let configuration = Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectionTimeout: .seconds(12),
            maximumMessageSize: 32 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 3,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let tip: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
            
            try await client.reconnect()
            
            let balance: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance = try await client.request(
                method: .blockchain(
                    .address(
                        .getBalance(address: Self.sampleCashAddress, tokenFilter: nil)
                    )
                ),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance.self
            )
            #expect(balance.confirmed >= 0)
            
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
    
    @Test("subscribes to address updates and supports cancellation", .timeLimit(.minutes(1)))
    func testSubscribeToAddressDeliversInitialSnapshot() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let (initial, updates, cancel) = try await client.subscribe(
                method: .blockchain(.address(.subscribe(address: Self.sampleCashAddress))),
                initialType: SwiftFulcrum.Response.Result.Blockchain.Address.Subscribe.self,
                notificationType: SwiftFulcrum.Response.Result.Blockchain.Address.SubscribeNotification.self
            )
            
            #expect(!(initial.status?.isEmpty ?? true))
            
            var iterator = updates.makeAsyncIterator()
            async let nextNotification = iterator.next()
            
            await cancel()
            
            let notification = try await nextNotification
            #expect(notification == nil || notification?.subscriptionIdentifier == Self.sampleCashAddress)
            if let notification {
                #expect(!(notification.status?.isEmpty ?? true))
            }
        }
    }
    
    @Test("subscribes to live header stream and cancels cleanly", .timeLimit(.minutes(1)))
    func testSubscribeReturnsStreamAndSupportsCancellation() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let (initial, stream, cancel) = try await client.subscribe(
                method: .blockchain(.headers(.subscribe)),
                initialType: SwiftFulcrum.Response.Result.Blockchain.Headers.Subscribe.self,
                notificationType: SwiftFulcrum.Response.Result.Blockchain.Headers.SubscribeNotification.self
            )
            
            #expect(initial.height > 0)
            #expect(!initial.hex.isEmpty)
            
            var iterator = stream.makeAsyncIterator()
            async let nextNotification: SwiftFulcrum.Response.Result.Blockchain.Headers.SubscribeNotification? = iterator.next()
            
            await cancel()
            
            let notification = try await nextNotification
            #expect(notification == nil)
        }
    }
}
