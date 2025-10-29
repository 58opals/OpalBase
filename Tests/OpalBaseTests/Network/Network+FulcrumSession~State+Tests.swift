import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession State Machine", .tags(.network, .integration))
struct NetworkFulcrumSessionStateMachineTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    
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
}

private actor TestStreamingCallDescriptor: Network.FulcrumSession.AnyStreamingCallDescriptor {
    enum Error: Swift.Error {
        case simulated
    }
    
    let identifier: UUID
    let method: SwiftFulcrum.Method
    let options: SwiftFulcrum.Client.Call.Options
    
    private let shouldThrowOnResubscribe: Bool
    private var recordedStates: [Network.FulcrumSession.State] = []
    private var prepareForRestartCount = 0
    
    init(method: SwiftFulcrum.Method = .blockchain(.headers(.getTip)),
         options: SwiftFulcrum.Client.Call.Options = .init(),
         shouldThrowOnResubscribe: Bool = false) {
        self.identifier = UUID()
        self.method = method
        self.options = options
        self.shouldThrowOnResubscribe = shouldThrowOnResubscribe
    }
    
    func prepareForRestart() async {
        prepareForRestartCount += 1
    }
    
    func cancelAndFinish() async {}
    
    func finish(with error: Swift.Error) async {}
    
    func resubscribe(using session: Network.FulcrumSession, fulcrum: SwiftFulcrum.Fulcrum) async throws {
        let currentState = await session.state
        recordedStates.append(currentState)
        
        if shouldThrowOnResubscribe {
            throw Error.simulated
        }
    }
    
    func readRecordedStates() async -> [Network.FulcrumSession.State] {
        recordedStates
    }
    
    func readPrepareForRestartCount() async -> Int {
        prepareForRestartCount
    }
}

extension Network.FulcrumSession {
    func addStreamingCallDescriptorForTesting(_ descriptor: any AnyStreamingCallDescriptor) {
        streamingCallDescriptors[descriptor.identifier] = descriptor
    }
}

extension NetworkFulcrumSessionStateMachineTests {
    @Test("start transitions from stopped through restoring to running", .timeLimit(.minutes(3)))
    func testStartTransitionsThroughRestoringToRunning() async throws {
        try await withSession { session in
            let descriptor = TestStreamingCallDescriptor()
            await session.addStreamingCallDescriptorForTesting(descriptor)
            
            try await session.start()
            
            let states = await descriptor.readRecordedStates()
            #expect(states.contains(.restoring))
            #expect(await session.state == .running)
        }
    }
    
    @Test("failed restoration returns the session to stopped", .timeLimit(.minutes(3)))
    func testRestoreFailureReturnsSessionToStopped() async throws {
        try await withSession { session in
            let descriptor = TestStreamingCallDescriptor(shouldThrowOnResubscribe: true)
            await session.addStreamingCallDescriptorForTesting(descriptor)
            
            do {
                try await session.start()
                #expect(Bool(false), "Expected start to throw when restoration fails")
            } catch let sessionError as Network.FulcrumSession.Error {
                guard case .failedToRestoreSubscription = sessionError else {
                    return #expect(Bool(false), "Unexpected session error: \(sessionError)")
                }
            }
            
            #expect(await session.state == .stopped)
            #expect(await descriptor.readPrepareForRestartCount() >= 1)
        }
    }
    
    @Test("start rejects attempts while already running", .timeLimit(.minutes(3)))
    func testStartRejectsWhileAlreadyRunning() async throws {
        try await withSession { session in
            try await session.start()
            #expect(await session.state == .running)
            
            do {
                try await session.start()
                #expect(Bool(false), "Expected start to throw when already running")
            } catch let sessionError as Network.FulcrumSession.Error {
                guard case .sessionAlreadyStarted = sessionError else {
                    return #expect(Bool(false), "Unexpected session error: \(sessionError)")
                }
            }
            
            #expect(await session.state == .running)
        }
    }
}
