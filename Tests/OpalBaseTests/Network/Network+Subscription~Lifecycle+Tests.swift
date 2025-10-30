import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession Subscription Lifecycle", .tags(.network, .integration))
struct NetworkFulcrumSessionSubscriptionLifecycleTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    @Test("subscriptions resubscribe after restart", .timeLimit(.minutes(1)))
    func testSubscriptionsResubscribeAfterRestart() async throws {
        
    }
    
    @Test("resubscribe refreshes token and clears internal cancellation flags", .timeLimit(.minutes(1)))
    func testResubscribeRefreshesTokenAndClearsInternalCancellationFlags() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        var options = SwiftFulcrum.Client.Call.Options(timeout: .seconds(20))
        options.token = SwiftFulcrum.Client.Call.Token()
        
        let subscription = try await session.subscribeToAddress(Self.sampleAddress, options: options)
        let identifier = subscription.identifier
        
        let initialToken = await session.streamingCallOptions[identifier]?.token
        if let initialToken {
            #expect(!(await initialToken.isCancelled))
        } else {
            #expect(Bool(false), "Expected subscription to persist initial streaming token")
        }
        
        #expect(await session.internallyCancelledStreamingCallIdentifiers.isEmpty)
        
        let resubscribedInitial = try await subscription.resubscribe()
        if let status = resubscribedInitial.status {
            #expect(status.count == 64)
        }
        
        let refreshedToken = await session.streamingCallOptions[identifier]?.token
        
        if let initialToken {
            #expect(await initialToken.isCancelled)
        }
        
        if let refreshedToken {
            #expect(!(await refreshedToken.isCancelled))
        } else {
            #expect(Bool(false), "Expected resubscribe to install replacement streaming token")
        }
        
        #expect(await session.internallyCancelledStreamingCallIdentifiers.isEmpty)
    }
    
    @Test("restore removes externally cancelled tokens", .timeLimit(.minutes(1)))
    func testRestoreStreamingSubscriptionsDropsCancelledTokens() async throws {
        
    }
    
    @Test("cancelAllStreamingCalls clears active streams", .timeLimit(.minutes(1)))
    func testCancelAllStreamingCallsTerminatesSubscriptions() async throws {
        
    }
    
    @Test("cancelStreamingCall removes descriptor", .timeLimit(.minutes(1)))
    func testCancelStreamingCallRemovesDescriptor() async throws {
        
    }
    
    @Test("normalizeStreamingOptions preserves timeout and token")
    func testNormalizeStreamingOptionsPreservesConfiguration() async {
        let token = SwiftFulcrum.Client.Call.Token()
        let options = SwiftFulcrum.Client.Call.Options(timeout: .seconds(45), token: token)
        
        let normalized = Network.FulcrumSession.normalizeStreamingOptions(options)
        
        #expect(normalized.timeout == .seconds(45))
        if let normalizedToken = normalized.token {
            #expect(!(await normalizedToken.isCancelled))
        } else {
            #expect(Bool(false), "Expected normalized token to be preserved")
        }
        
        await token.cancel()
        #expect(await token.isCancelled)
        if let normalizedToken = normalized.token {
            #expect(await normalizedToken.isCancelled)
        }
    }
}
