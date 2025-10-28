import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession Subscriptions", .tags(.network, .integration))
struct NetworkFulcrumSessionSubscriptionTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    private func withSession(
        using serverAddress: URL = Self.healthyServerAddress,
        configuration: SwiftFulcrum.Fulcrum.Configuration = .init(),
        perform: @escaping @Sendable (Network.FulcrumSession) async throws -> Void
    ) async throws {
        let session = try await Network.FulcrumSession(serverAddress: serverAddress, configuration: configuration)
        
        do {
            try await perform(session)
        } catch {
            if await session.isRunning {
                try await session.stop()
            }
            #expect(await !session.isRunning)
            throw error
        }
        
        if await session.isRunning {
            try await session.stop()
        }
        #expect(await !session.isRunning)
    }
    
    private func withRunningSession(
        using serverAddress: URL = Self.healthyServerAddress,
        configuration: SwiftFulcrum.Fulcrum.Configuration = .init(),
        perform: @escaping @Sendable (Network.FulcrumSession) async throws -> Void
    ) async throws {
        try await withSession(using: serverAddress, configuration: configuration) { session in
            try await session.start()
            #expect(await session.isRunning)
            try await perform(session)
        }
    }
    
    private func makeScriptHash(for address: String) throws -> String {
        let address = try Address(address)
        let lockingScript = address.lockingScript.data
        let digest = SHA256.hash(lockingScript)
        return Data(digest.reversed()).map { String(format: "%02x", $0) }.joined()
    }
}

extension NetworkFulcrumSessionSubscriptionTests {
    @Test("subscription resubscribes after preparing for restart")
    func testScriptHashSubscriptionRecoversAfterRestartPreparation() async throws {
        try await withRunningSession { session in
            let scriptHash = try makeScriptHash(for: Self.sampleAddress)
            let subscription = try await session.subscribeToScriptHash(scriptHash)
            defer { Task { await subscription.cancel() } }
            
            let initialStatus = await subscription.fetchLatestInitialResponse()
            #expect(initialStatus.status != nil)
            #expect(await subscription.checkIsActive())
            
            await session.prepareStreamingCallsForRestart()
            #expect(await !subscription.checkIsActive())
            
            let refreshedStatus = try await subscription.resubscribe()
            let latestStatus = await subscription.fetchLatestInitialResponse()
            
            #expect(refreshedStatus.status == latestStatus.status)
            #expect(await subscription.checkIsActive())
        }
    }
    
    @Test("canceling subscriptions finishes the update stream")
    func testScriptHashSubscriptionCancellationFinishesStream() async throws {
        try await withRunningSession { session in
            let scriptHash = try makeScriptHash(for: Self.sampleAddress)
            let subscription = try await session.subscribeToScriptHash(scriptHash)
            
            let updateTask = Task { () -> SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification? in
                var iterator = subscription.updates.makeAsyncIterator()
                return try await iterator.next()
            }
            
            try await Task.sleep(nanoseconds: 1_000_000_000)
            await subscription.cancel()
            
            let receivedUpdate = try await updateTask.value
            #expect(receivedUpdate == nil)
            #expect(await !subscription.checkIsActive())
        }
    }
}
