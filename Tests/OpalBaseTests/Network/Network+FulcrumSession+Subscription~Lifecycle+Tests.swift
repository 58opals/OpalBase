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
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let token = SwiftFulcrum.Client.Call.Token()
        var options = SwiftFulcrum.Client.Call.Options(timeout: .seconds(30))
        options.token = token
        
        let subscription = try await session.subscribeToAddress(Self.sampleAddress, options: options)
        
        let initialStatus = await subscription.fetchLatestInitialResponse().status
        if let status = initialStatus {
            #expect(status.count == 64)
        }
        
        #expect(await subscription.checkIsActive())
        let resubscribedInitial = try await subscription.resubscribe()
        if let status = resubscribedInitial.status {
            #expect(status.count == 64)
        }
        
        await session.prepareStreamingCallsForRestart()
        
        #expect(await session.state == .stopped)
        #expect(await session.activeServerAddress == nil)
        #expect(!(await subscription.checkIsActive()))
        
        let configuration = await session.configuration
        let fulcrum = try await SwiftFulcrum.Fulcrum(url: Self.healthyServerAddress.absoluteString, configuration: configuration)
        try await fulcrum.start()
        defer { Task { await fulcrum.stop() } }
        
        try await session.restoreStreamingSubscriptions(using: fulcrum)
        
        #expect(await subscription.checkIsActive())
        let latestStatus = await subscription.fetchLatestInitialResponse().status
        if let status = latestStatus {
            #expect(status.count == 64)
        }
        
        print(await session.streamingCallDescriptors)
        let descriptorCount = await session.streamingCallDescriptors.count
        #expect(descriptorCount == 1)
    }
    
    @Test("restore removes externally cancelled tokens", .timeLimit(.minutes(1)))
    func testRestoreStreamingSubscriptionsDropsCancelledTokens() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let token = SwiftFulcrum.Client.Call.Token()
        var options = SwiftFulcrum.Client.Call.Options(timeout: .seconds(15))
        options.token = token
        
        let subscription = try await session.subscribeToAddress(Self.sampleAddress, options: options)
        
        #expect(await subscription.checkIsActive())
        
        await token.cancel()
        #expect(await token.isCancelled)
        
        guard let fulcrum = await session.fulcrum else {
            #expect(Bool(false), "Expected active fulcrum instance")
            return
        }
        
        try await session.restoreStreamingSubscriptions(using: fulcrum)
        
        let remainingDescriptors = await session.streamingCallDescriptors.count
        #expect(remainingDescriptors == 0)
        
        let isActive = await subscription.checkIsActive()
        #expect(!isActive)
    }
    
    @Test("cancelAllStreamingCalls clears active streams", .timeLimit(.minutes(1)))
    func testCancelAllStreamingCallsTerminatesSubscriptions() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let subscription = try await session.subscribeToAddress(Self.sampleAddress)
        
        let initialDescriptorCount = await session.streamingCallDescriptors.count
        #expect(initialDescriptorCount == 1)
        
        await session.cancelAllStreamingCalls()
        
        let descriptorsAfterCancellation = await session.streamingCallDescriptors.isEmpty
        let optionsAfterCancellation = await session.streamingCallOptions.isEmpty
        #expect(descriptorsAfterCancellation)
        #expect(optionsAfterCancellation)
        
        var iterator = subscription.updates.makeAsyncIterator()
        let nextUpdate = try await iterator.next()
        #expect(nextUpdate == nil)
    }
    
    @Test("cancelStreamingCall removes descriptor", .timeLimit(.minutes(1)))
    func testCancelStreamingCallRemovesDescriptor() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let subscription = try await session.subscribeToAddress(Self.sampleAddress)
        
        let descriptorCountBeforeCancel = await session.streamingCallDescriptors.count
        #expect(descriptorCountBeforeCancel == 1)
        
        await subscription.cancel()
        
        let descriptorsAfterCancel = await session.streamingCallDescriptors.isEmpty
        let optionsAfterCancel = await session.streamingCallOptions.isEmpty
        #expect(descriptorsAfterCancel)
        #expect(optionsAfterCancel)
        #expect(!(await subscription.checkIsActive()))
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
