// NetworkFulcrumClientValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.Client", .tags(.integration, .network))
struct NetworkFulcrumClientValidator {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50004")!
    private static let faultyServerAddress = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    private static let invalidServerAddress = URL(string: "not a url")!
    private static let sampleCashAddr = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let invalidCashAddr = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
    
    @Test("performs wallet-centric requests and reconnects", .timeLimit(.minutes(1)))
    func walletOperationsWithLiveFulcrum() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 4,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )
        
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let storedConfiguration = await client.configuration
            #expect(storedConfiguration == configuration)
            
            let tip: SwiftFulcrum.Response.Blockchain.Headers.GetTip = try await client.request(
                .blockchain.headers.getTip
            )
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
            
            let balance: SwiftFulcrum.Response.Blockchain.Address.GetBalance = try await client.request(
                .blockchain.address.getBalance(address: Self.sampleCashAddr, tokenFilter: .include)
            )
            _ = balance
            
            try await client.reconnect()
            
            let history: SwiftFulcrum.Response.Blockchain.Address.GetHistory = try await client.request(
                .blockchain.address.getHistory(
                    address: Self.sampleCashAddr,
                    shouldIncludeUnconfirmed: true
                )
            )
            #expect(!history.transactions.isEmpty)
        }
    }
    
    @Test("performs wallet critical unary calls and reconnects", .timeLimit(.minutes(1)))
    func clientPerformsWalletCriticalRequests() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectTimeout: .seconds(12),
            maximumMessageSize: 32 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 3,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )
        
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let tip: SwiftFulcrum.Response.Blockchain.Headers.GetTip = try await client.request(
                .blockchain.headers.getTip
            )
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
            
            try await client.reconnect()
            
            let balance: SwiftFulcrum.Response.Blockchain.Address.GetBalance = try await client.request(
                .blockchain.address.getBalance(address: Self.sampleCashAddr, tokenFilter: .include)
            )
            _ = balance
            
            let history: SwiftFulcrum.Response.Blockchain.Address.GetHistory = try await client.request(
                .blockchain.address.getHistory(
                    address: Self.sampleCashAddr,
                    shouldIncludeUnconfirmed: true
                )
            )
            #expect(!history.transactions.isEmpty)
        }
    }
    
    @Test("subscribes to address updates and supports cancellation", .timeLimit(.minutes(1)))
    func subscribeToAddressDeliversInitialSnapshot() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let (initial, updates, cancel) = try await client.subscribe(
                .blockchain.address.subscribe(address: Self.sampleCashAddr)
            )
            
            #expect(!(initial.status?.isEmpty ?? true))
            
            var iterator = updates.makeAsyncIterator()
            async let nextNotification = iterator.next()
            
            await cancel()
            
            let notification = try await nextNotification
            #expect(notification == nil || notification?.subscriptionIdentifier == Self.sampleCashAddr)
            if let notification {
                #expect(!(notification.status?.isEmpty ?? true))
            }
        }
    }
    
    @Test("subscribes to live header stream and cancels cleanly", .timeLimit(.minutes(1)))
    func subscribeReturnsStreamAndSupportsCancellation() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let (initial, stream, cancel) = try await client.subscribe(
                .blockchain.headers.subscribe
            )
            
            #expect(initial.height > 0)
            #expect(!initial.hex.isEmpty)
            
            var iterator = stream.makeAsyncIterator()
            async let nextNotification: SwiftFulcrum.Response.Blockchain.Headers.SubscribeNotification? = iterator.next()
            
            await cancel()
            
            let notification = try await nextNotification
            #expect(notification == nil)
        }
    }
}
