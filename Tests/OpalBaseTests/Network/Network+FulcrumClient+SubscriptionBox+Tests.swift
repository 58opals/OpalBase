import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumClient.SubscriptionBox", .tags(.network))
struct NetworkFulcrumClientSubscriptionBoxTests {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    @Test("establishes live subscription, resubscribes, and cancels", .timeLimit(.minutes(1)))
    func testSubscriptionLifecycleResubscribesAndCancels() async throws {
        let reconnectConfiguration = Fulcrum.Configuration.Reconnect(
            maximumReconnectionAttempts: 2,
            reconnectionDelay: 1,
            maximumDelay: 5,
            jitterRange: 0.9 ... 1.1
        )
        
        let fulcrumConfiguration = Fulcrum.Configuration(
            reconnect: reconnectConfiguration,
            metrics: nil,
            logger: nil,
            urlSession: nil,
            connectionTimeout: 12,
            maximumMessageSize: 16 * 1_024 * 1_024,
            bootstrapServers: [Self.primaryServerAddress, Self.backupServerAddress]
        )
        
        let fulcrum = try await Fulcrum(configuration: fulcrumConfiguration)
        
        do {
            try await fulcrum.start()
            
            let (terminationStream, terminationContinuation) = AsyncStream<UUID>.makeStream()
            
            let subscription = Network.FulcrumSubscriptionBox<
                SwiftFulcrum.Response.Result.Blockchain.Address.Subscribe,
                SwiftFulcrum.Response.Result.Blockchain.Address.SubscribeNotification
            >(
                method: .blockchain(.address(.subscribe(address: Self.sampleCashAddress))),
                options: .init()
            ) { identifier in
                terminationContinuation.yield(identifier)
            }
            
            let initial = try await subscription.establish(using: fulcrum)
            #expect(!(initial.status?.isEmpty ?? true))
            
            var iterator = await subscription.stream.makeAsyncIterator()
            let pendingUpdate = Task<SwiftFulcrum.Response.Result.Blockchain.Address.SubscribeNotification?, Swift.Error> {
                try await iterator.next()
            }
            
            await subscription.prepareForReconnect()
            await subscription.resubscribe(using: fulcrum)
            
            await subscription.cancel()
            
            let update = try await pendingUpdate.value
            #expect(update == nil || !(update?.status?.isEmpty ?? true))
            
            var terminationIterator = terminationStream.makeAsyncIterator()
            if let identifier = await terminationIterator.next() {
                let subscriptionID = await subscription.id
                #expect(identifier == subscriptionID)
            } else {
                Issue.record("Expected termination notification before stream completed")
            }
            
            terminationContinuation.finish()
            await fulcrum.stop()
        } catch {
            await fulcrum.stop()
            throw error
        }
    }
    
    @Test("establishes live address subscription and cancels gracefully", .timeLimit(.minutes(1)))
    func testSubscriptionBoxCancelsWithTerminationNotification() async throws {
        let configuration = Fulcrum.Configuration(
            reconnect: .init(
                maximumReconnectionAttempts: 3,
                reconnectionDelay: 1.5,
                maximumDelay: 12,
                jitterRange: 0.9 ... 1.2
            ),
            connectionTimeout: 12,
            maximumMessageSize: 16 * 1_024 * 1_024,
            bootstrapServers: [Self.primaryServerAddress, Self.backupServerAddress]
        )
        
        let fulcrum = try await Fulcrum(configuration: configuration)
        try await fulcrum.start()
        
        do {
            let (terminationStream, terminationContinuation) = AsyncStream<UUID>.makeStream()
            let terminationTask = Task { () -> [UUID] in
                var identifiers: [UUID] = .init()
                for await identifier in terminationStream {
                    identifiers.append(identifier)
                }
                return identifiers
            }
            
            let subscription = Network.FulcrumSubscriptionBox<
                SwiftFulcrum.Response.Result.Blockchain.Address.Subscribe,
                SwiftFulcrum.Response.Result.Blockchain.Address.SubscribeNotification
            >(
                method: .blockchain(.address(.subscribe(address: Self.sampleCashAddress))),
                options: .init()
            ) { identifier in
                terminationContinuation.yield(identifier)
                terminationContinuation.finish()
            }
            
            let initial = try await subscription.establish(using: fulcrum)
            #expect(!(initial.status?.isEmpty ?? true))
            
            var iterator = await subscription.stream.makeAsyncIterator()
            async let pendingNotification = iterator.next()
            try await Task.sleep(for: .seconds(1))
            
            await subscription.cancel()
            await subscription.cancel()
            
            do {
                if let notification = try await pendingNotification {
                    #expect(notification.subscriptionIdentifier == Self.sampleCashAddress)
                    #expect(!(notification.status?.isEmpty ?? true))
                }
            } catch {
                Issue.record("Unexpected error when awaiting subscription notification: \(error)")
            }
            
            let terminationIdentifiers = await terminationTask.value
            let subscriptionIdentifier = await subscription.id
            #expect(terminationIdentifiers == [subscriptionIdentifier])
            
            await fulcrum.stop()
        } catch {
            await fulcrum.stop()
            throw error
        }
    }
}
