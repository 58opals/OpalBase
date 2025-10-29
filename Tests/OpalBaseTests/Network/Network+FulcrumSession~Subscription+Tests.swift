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
            #expect(await session.state == .stopped)
            throw error
        }
        
        if await session.isRunning {
            try await session.stop()
        }
        #expect(await session.state == .stopped)
    }
    
    private func withRunningSession(
        using serverAddress: URL = Self.healthyServerAddress,
        configuration: SwiftFulcrum.Fulcrum.Configuration = .init(),
        perform: @escaping @Sendable (Network.FulcrumSession) async throws -> Void
    ) async throws {
        try await withSession(using: serverAddress, configuration: configuration) { session in
            try await session.start()
            #expect(await session.state == .running)
            try await perform(session)
        }
    }
    
    private func makeScriptHash(for address: String) throws -> String {
        let address = try Address(address)
        let lockingScript = address.lockingScript.data
        let digest = SHA256.hash(lockingScript)
        return Data(digest.reversed()).map { String(format: "%02x", $0) }.joined()
    }
    
    private func readScriptHashDescriptor(
        from session: Network.FulcrumSession,
        identifier: UUID
    ) async -> StreamingCallDescriptor<SwiftFulcrum.Response.Result.Blockchain.ScriptHash.Subscribe, SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification>? {
        await session.streamingCallDescriptors[identifier] as? StreamingCallDescriptor<SwiftFulcrum.Response.Result.Blockchain.ScriptHash.Subscribe, SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification>
    }
}

extension NetworkFulcrumSessionSubscriptionTests {
    @Test("subscription resubscribes after preparing for restart", .timeLimit(.minutes(3)))
    func testScriptHashSubscriptionRecoversAfterRestartPreparation() async throws {
        try await withRunningSession { session in
            let scriptHash = try makeScriptHash(for: Self.sampleAddress)
            let subscription = try await session.subscribeToScriptHash(scriptHash)
            defer { Task { await subscription.cancel() } }
            
            let initialStatus = await subscription.fetchLatestInitialResponse()
            #expect(initialStatus.status != nil)
            #expect(await subscription.checkIsActive())
            
            await session.prepareStreamingCallsForRestart()
            #expect(await session.fulcrum == nil)
            #expect(await !session.isRunning)
            #expect(await session.state == .stopped)
            #expect(await !subscription.checkIsActive())
            
            try await session.start()
            #expect(await session.isRunning)
            #expect(await session.state == .running)
            #expect(await subscription.checkIsActive())
            
            let refreshedStatus = try await subscription.resubscribe()
            let latestStatus = await subscription.fetchLatestInitialResponse()
            
            #expect(refreshedStatus.status == latestStatus.status)
            #expect(await subscription.checkIsActive())
        }
    }
    
    @Test("canceling subscriptions finishes the update stream", .timeLimit(.minutes(3)))
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
    
    @Test("resubscribeExisting succeeds while running", .timeLimit(.minutes(3)))
    func testResubscribeExistingSucceedsWhileRunning() async throws {
        try await withRunningSession { session in
            let scriptHash = try makeScriptHash(for: Self.sampleAddress)
            let subscription = try await session.subscribeToScriptHash(scriptHash)
            
            guard let descriptor = await readScriptHashDescriptor(from: session, identifier: subscription.identifier) else {
                return #expect(Bool(false), "Expected to find the subscription descriptor")
            }
            
            let refreshed = try await session.resubscribeExisting(descriptor)
            let latest = await subscription.fetchLatestInitialResponse()
            
            #expect(refreshed.status == latest.status)
            #expect(await session.state == .running)
        }
    }
    
    @Test("resubscribeExisting fails while stopped", .timeLimit(.minutes(3)))
    func testResubscribeExistingFailsWhileStopped() async throws {
        try await withRunningSession { session in
            let scriptHash = try makeScriptHash(for: Self.sampleAddress)
            let subscription = try await session.subscribeToScriptHash(scriptHash)
            
            guard let descriptor = await readScriptHashDescriptor(from: session, identifier: subscription.identifier) else {
                return #expect(Bool(false), "Expected to find the subscription descriptor")
            }
            
            await session.prepareStreamingCallsForRestart()
            #expect(await session.state == .stopped)
            
            do {
                _ = try await session.resubscribeExisting(descriptor)
                #expect(Bool(false), "Expected resubscribeExisting to throw when the session is stopped")
            } catch let sessionError as Network.FulcrumSession.Error {
                guard case .sessionNotStarted = sessionError else {
                    return #expect(Bool(false), "Unexpected session error: \(sessionError)")
                }
            }
        }
    }
}

private actor SubscriptionRestorationDescriptor: AnyStreamingCallDescriptor {
    enum Mode {
        case succeed
        case fail(Swift.Error)
    }
    
    let identifier: UUID = .init()
    let method: SwiftFulcrum.Method = .blockchain(.headers(.getTip))
    let options: SwiftFulcrum.Client.Call.Options = .init()
    
    private let mode: Mode
    private var observedStates: [Network.FulcrumSession.State] = []
    private var prepareCount = 0
    
    init(mode: Mode) {
        self.mode = mode
    }
    
    func prepareForRestart() async {
        prepareCount += 1
    }
    
    func cancelAndFinish() async {}
    
    func finish(with error: Swift.Error) async {}
    
    func resubscribe(using session: Network.FulcrumSession, fulcrum: SwiftFulcrum.Fulcrum) async throws {
        let currentState = await session.state
        observedStates.append(currentState)
        
        switch mode {
        case .succeed:
            return
        case .fail(let error):
            throw error
        }
    }
    
    func readObservedStates() async -> [Network.FulcrumSession.State] {
        observedStates
    }
    
    func readPrepareCount() async -> Int {
        prepareCount
    }
}

extension NetworkFulcrumSessionSubscriptionTests {
    @Test("resubscribeExisting succeeds while restoring", .timeLimit(.minutes(3)))
    func testResubscribeExistingSucceedsWhileRestoring() async throws {
        try await withSession { session in
            let descriptor = SubscriptionRestorationDescriptor(mode: .succeed)
            await session.addStreamingCallDescriptorForTesting(descriptor)
            
            try await session.start()
            
            let states = await descriptor.readObservedStates()
            #expect(states.contains(.restoring))
            #expect(await session.state == .running)
        }
    }
    
    @Test("resubscribeExisting failure during restoring records errors", .timeLimit(.minutes(3)))
    func testResubscribeExistingFailureDuringRestoringRecordsErrors() async throws {
        try await withSession { session in
            let descriptor = SubscriptionRestorationDescriptor(mode: .fail(Network.FulcrumSession.Error.subscriptionNotFound))
            await session.addStreamingCallDescriptorForTesting(descriptor)
            
            do {
                try await session.start()
                #expect(Bool(false), "Expected start to throw when restoration fails")
            } catch let sessionError as Network.FulcrumSession.Error {
                guard case .failedToRestoreSubscription(let underlyingError) = sessionError else {
                    return #expect(Bool(false), "Unexpected session error: \(sessionError)")
                }
                
                if let nestedError = underlyingError as? Network.FulcrumSession.Error {
                    guard case .subscriptionNotFound = nestedError else {
                        return #expect(Bool(false), "Unexpected underlying error: \(nestedError)")
                    }
                } else {
                    #expect(Bool(false), "Expected the underlying error to be a session error")
                }
            }
            
            #expect(await session.state == .stopped)
            #expect(await descriptor.readPrepareCount() >= 1)
        }
    }
}
