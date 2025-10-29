import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession Subscription Lifecycle", .tags(.network, .integration))
struct NetworkFulcrumSessionSubscriptionLifecycleTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let sampleScriptHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    
    // MARK: Session requirements
    
    @Test("makeSubscription fails when the session is not running")
    func makeSubscriptionRequiresRunningSession() async throws {
        let session = try await makeSession()
        await session.testingSetState(.stopped)
        
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            _ = try await session.makeSubscription(
                method: .blockchain(.address(.subscribe(address: Self.sampleAddress))),
                initialType: DummyInitial.self,
                notificationType: DummyNotification.self,
                options: .init()
            )
        }
    }
    
    @Test("resubscribeExisting throws when stopped and tears down the stale stream")
    func resubscribeExistingWhenSessionStoppedThrowsAndCancels() async throws {
        let session = try await makeSession()
        await session.testingSetState(.stopped)
        
        let cancels = CancellationRecorder()
        let descriptor = await makeStreamingDescriptor(cancelRecorder: cancels)
        
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            _ = try await session.resubscribeExisting(descriptor)
        }
        #expect(await cancels.read() == 1)
    }
    
    // MARK: Restart preparation
    
    @Test("prepareForRestart pauses streams, clears Fulcrum, and stops the session")
    func prepareStreamingCallsForRestartPausesAndResets() async throws {
        let session = try await makeSession()
        await session.testingSetState(.running)
        
        let pauseCancels = CancellationRecorder()
        let streamingDescriptor = await makeStreamingDescriptor(cancelRecorder: pauseCancels)
        
        let spy = LifecycleSpyDescriptor(method: .blockchain(.headers(.subscribe)))
        await session.testingStoreDescriptor(streamingDescriptor)
        await session.testingStoreDescriptor(spy)
        
        let fulcrum = try await makeFulcrum()
        await session.testingSetFulcrum(fulcrum)
        
        await session.prepareStreamingCallsForRestart()
        
        #expect(await spy.readPrepareCount() == 1)
        #expect(await spy.readCancelAndFinishCount() == 0)
        #expect(await pauseCancels.read() == 1)
        #expect(await session.testingReadState() == .stopped)
        #expect(await session.testingReadFulcrum() == nil)
        #expect(await session.testingDescriptorCount() == 2)
    }
    
    // MARK: Shutdown
    
    @Test("cancelAllStreamingCalls drains every descriptor and clears the registry")
    func cancelAllStreamingCallsFinishesAndClears() async throws {
        let session = try await makeSession()
        await session.testingSetState(.running)
        
        let first = CancellationRecorder()
        let second = CancellationRecorder()
        let firstDescriptor = await makeStreamingDescriptor(cancelRecorder: first)
        let secondDescriptor = await makeStreamingDescriptor(
            method: .blockchain(.headers(.subscribe)),
            cancelRecorder: second
        )
        
        await session.testingStoreDescriptor(firstDescriptor)
        await session.testingStoreDescriptor(secondDescriptor)
        
        await session.cancelAllStreamingCalls()
        
        #expect(await first.read() == 1)
        #expect(await second.read() == 1)
        #expect(await session.testingDescriptorCount() == 0)
    }
    
    @Test("cancelStreamingCall ignores unknown identifiers")
    func cancelStreamingCallIgnoresUnknownDescriptor() async throws {
        let session = try await makeSession()
        await session.testingSetState(.running)
        
        let cancels = CancellationRecorder()
        let descriptor = await makeStreamingDescriptor(cancelRecorder: cancels)
        
        await session.cancelStreamingCall(for: descriptor)
        
        #expect(await cancels.read() == 0)
        #expect(await session.testingDescriptorCount() == 0)
    }
    
    @Test("cancelStreamingCall removes the subscription and invokes its cancel handler")
    func cancelStreamingCallRemovesDescriptor() async throws {
        let session = try await makeSession()
        await session.testingSetState(.running)
        
        let cancels = CancellationRecorder()
        let keep = await makeStreamingDescriptor(
            method: .blockchain(.scripthash(.subscribe(scripthash: Self.sampleScriptHash))),
            cancelRecorder: CancellationRecorder()
        )
        let drop = await makeStreamingDescriptor(cancelRecorder: cancels)
        
        await session.testingStoreDescriptor(keep)
        await session.testingStoreDescriptor(drop)
        
        await session.cancelStreamingCall(for: drop)
        
        #expect(await cancels.read() == 1)
        #expect(await session.testingDescriptorCount() == 1)
        #expect(await session.testingHasDescriptor(drop.identifier) == false)
        #expect(await session.testingHasDescriptor(keep.identifier))
    }
    
    // MARK: Restore after reconnect
    
    @Test("restoreStreamingSubscriptions resubscribes healthy descriptors")
    func restoreStreamingSubscriptionsResubscribesDescriptors() async throws {
        let session = try await makeSession()
        await session.testingSetState(.restoring)
        
        let fulcrum = try await makeFulcrum()
        defer { Task { await fulcrum.stop() } }
        
        let a = LifecycleSpyDescriptor(method: .blockchain(.address(.subscribe(address: Self.sampleAddress))))
        let b = LifecycleSpyDescriptor(method: .blockchain(.headers(.subscribe)))
        
        await session.testingStoreDescriptor(a)
        await session.testingStoreDescriptor(b)
        
        try await session.restoreStreamingSubscriptions(using: fulcrum)
        
        #expect(await a.readResubscribeCount() == 1)
        #expect(await b.readResubscribeCount() == 1)
        #expect(await a.readPrepareCount() == 0)
        #expect(await b.readPrepareCount() == 0)
    }
    
    @Test("restoreStreamingSubscriptions propagates first failure and prepares that descriptor for restart")
    func restoreStreamingSubscriptionsPropagatesFirstError() async throws {
        let session = try await makeSession()
        await session.testingSetState(.restoring)
        
        let fulcrum = try await makeFulcrum()
        defer { Task { await fulcrum.stop() } }
        
        let failingError = TestError.simulated("resubscribe failure")
        let failing = LifecycleSpyDescriptor(
            method: .blockchain(.scripthash(.subscribe(scripthash: Self.sampleScriptHash))),
            behavior: .fail(failingError)
        )
        let healthy = LifecycleSpyDescriptor(
            method: .blockchain(.address(.subscribe(address: Self.sampleAddress)))
        )
        
        await session.testingStoreDescriptor(failing)
        await session.testingStoreDescriptor(healthy)
        
        await #expect(throws: Network.FulcrumSession.Error.failedToRestoreSubscription(failingError)) {
            try await session.restoreStreamingSubscriptions(using: fulcrum)
        }
        
        #expect(await failing.readPrepareCount() == 1)
        #expect(await healthy.readPrepareCount() == 0)
        #expect(await failing.readResubscribeCount() == 1)
        #expect(await healthy.readResubscribeCount() == 1)
    }
    
    @Test("restoreStreamingSubscriptions requires running or restoring session")
    func restoreStreamingSubscriptionsRequiresOperationalState() async throws {
        let session = try await makeSession()
        await session.testingSetState(.stopped)
        
        let fulcrum = try await makeFulcrum()
        defer { Task { await fulcrum.stop() } }
        
        let descriptor = LifecycleSpyDescriptor(
            method: .blockchain(.address(.subscribe(address: Self.sampleAddress)))
        )
        await session.testingStoreDescriptor(descriptor)
        
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            try await session.restoreStreamingSubscriptions(using: fulcrum)
        }
    }
    
    @Test("restoreStreamingSubscriptions tolerates an empty descriptor collection")
    func restoreStreamingSubscriptionsWhenEmpty() async throws {
        let session = try await makeSession()
        await session.testingSetState(.restoring)
        
        let fulcrum = try await makeFulcrum()
        defer { Task { await fulcrum.stop() } }
        
        try await session.restoreStreamingSubscriptions(using: fulcrum)
        #expect(await session.testingDescriptorCount() == 0)
    }
    
    // MARK: Accessors
    
    @Test("subscription accessors surface cached initial state and activity")
    func readLatestInitialResponseAndActivity() async throws {
        let session = try await makeSession()
        await session.testingSetState(.running)
        
        let cancels = CancellationRecorder()
        let descriptor = await makeStreamingDescriptor(
            initial: DummyInitial(value: 21_000_000),
            cancelRecorder: cancels
        )
        await session.testingStoreDescriptor(descriptor)
        
        let latest = await session.readLatestInitialResponse(for: descriptor)
        #expect(latest.value == 21_000_000)
        
        #expect(await session.readIsStreamingCallActive(descriptor))
        await session.cancelStreamingCall(for: descriptor)
        #expect(await session.readIsStreamingCallActive(descriptor) == false)
        #expect(await cancels.read() == 1)
    }
    
    // MARK: Options
    
    @Test("normalize streaming options removes call token but preserves timeout")
    func normalizeStreamingOptionsRemovesToken() async {
        let token = SwiftFulcrum.Client.Call.Token()
        let options = SwiftFulcrum.Client.Call.Options(timeout: .seconds(30), token: token)
        let normalized = Network.FulcrumSession.normalizeStreamingOptions(options)
        
        #expect(normalized.timeout == .seconds(30))
        #expect(normalized.token == nil)
    }
}

// MARK: - Helpers

private extension NetworkFulcrumSessionSubscriptionLifecycleTests {
    func makeSession() async throws -> Network.FulcrumSession {
        try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
    }
    
    func makeFulcrum() async throws -> SwiftFulcrum.Fulcrum {
        try await SwiftFulcrum.Fulcrum(
            url: Self.healthyServerAddress.absoluteString,
            configuration: .init(bootstrapServers: [Self.healthyServerAddress])
        )
    }
    
    func makeStreamingDescriptor(
        method: SwiftFulcrum.Method = .blockchain(.address(.subscribe(address: sampleAddress))),
        initial: DummyInitial = .init(value: 0),
        cancelRecorder: CancellationRecorder
    ) async -> Network.FulcrumSession.StreamingCallDescriptor<DummyInitial, DummyNotification> {
        let (stream, continuation) = AsyncThrowingStream<DummyNotification, Swift.Error>.makeStream()
        
        return await Network.FulcrumSession.StreamingCallDescriptor(
            identifier: UUID(),
            method: method,
            options: .init(),
            initial: initial,
            updates: stream,
            cancel: {
                await cancelRecorder.increment()
                continuation.finish()
            }
        )
    }
}

// MARK: - Spies

private actor LifecycleSpyDescriptor: Network.FulcrumSession.AnyStreamingCallDescriptor {
    enum Behavior { case succeed, fail(Swift.Error) }
    
    let identifier: UUID
    let method: SwiftFulcrum.Method
    let options: SwiftFulcrum.Client.Call.Options
    
    private let behavior: Behavior
    private var prepareCount = 0
    private var cancelAndFinishCount = 0
    private var resubscribeCount = 0
    private var finishErrors: [Swift.Error] = []
    
    init(
        identifier: UUID = .init(),
        method: SwiftFulcrum.Method,
        options: SwiftFulcrum.Client.Call.Options = .init(),
        behavior: Behavior = .succeed
    ) {
        self.identifier = identifier
        self.method = method
        self.options = options
        self.behavior = behavior
    }
    
    func prepareForRestart() async { prepareCount += 1 }
    func cancelAndFinish() async { cancelAndFinishCount += 1 }
    func finish(with error: Swift.Error) async { finishErrors.append(error) }
    
    func resubscribe(using session: Network.FulcrumSession, fulcrum: SwiftFulcrum.Fulcrum) async throws {
        _ = session
        _ = fulcrum
        resubscribeCount += 1
        if case .fail(let error) = behavior { throw error }
    }
    
    func readPrepareCount() -> Int { prepareCount }
    func readCancelAndFinishCount() -> Int { cancelAndFinishCount }
    func readResubscribeCount() -> Int { resubscribeCount }
    func readFinishErrors() -> [Swift.Error] { finishErrors }
}

private actor CancellationRecorder {
    private var count = 0
    func increment() { count += 1 }
    func read() -> Int { count }
}

// MARK: - Test types

private struct DummyInitial: JSONRPCConvertible, Sendable {
    typealias JSONRPC = Int
    let value: Int
    
    init(value: Int) { self.value = value }
    
    init(fromRPC jsonrpc: Int) {
        self.value = jsonrpc
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.value = try c.decode(Int.self)
    }
}

private struct DummyNotification: JSONRPCConvertible, Sendable {
    typealias JSONRPC = String
    let message: String
    
    init(message: String) { self.message = message }
    
    init(fromRPC jsonrpc: String) {
        self.message = jsonrpc
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.message = try c.decode(String.self)
    }
}

private enum TestError: Swift.Error, Equatable {
    case simulated(String)
}

// MARK: - Test-only accessors

private extension Network.FulcrumSession {
    func testingSetState(_ newState: State) { state = newState }
    func testingReadState() -> State { state }
    
    func testingStoreDescriptor(_ descriptor: any AnyStreamingCallDescriptor) {
        streamingCallDescriptors[descriptor.identifier] = descriptor
    }
    
    func testingDescriptorCount() -> Int { streamingCallDescriptors.count }
    func testingHasDescriptor(_ id: UUID) -> Bool { streamingCallDescriptors[id] != nil }
    
    func testingSetFulcrum(_ f: SwiftFulcrum.Fulcrum?) { fulcrum = f }
    func testingReadFulcrum() -> SwiftFulcrum.Fulcrum? { fulcrum }
}
