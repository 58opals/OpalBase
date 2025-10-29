import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession State", .tags(.network))
struct NetworkFulcrumSessionStateTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let unreachableServerAddress = URL(string: "wss://127.0.0.1:65535")!
    private enum TestError: Swift.Error {
        case timedOutWaitingForEvent
    }
    
    private static let eventTimeout: Duration = .seconds(10)
    
    // MARK: - Lifecycle and readiness
    
    @Test("sessions start in a stopped state", .tags(.unit))
    func testSessionStartsStopped() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        
        let state = await session.state
        #expect(state == .stopped)
        #expect(await session.isRunning == false)
        #expect(await session.isOperational == false)
        #expect(await session.activeServerAddress == nil)
    }
    
    @Test("ensure session ready enforces lifecycle gates", .tags(.unit))
    func testEnsureSessionReadyEnforcesLifecycleGates() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        
        await session.updateStateForTesting(to: .stopped)
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            try await session.ensureSessionReady()
        }
        
        await session.updateStateForTesting(to: .restoring)
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            try await session.ensureSessionReady()
        }
        
        try await session.ensureSessionReady(allowRestoring: true)
        
        await session.updateStateForTesting(to: .running)
        try await session.ensureSessionReady()
        #expect(await session.isRunning)
    }
    
    @Test("operational flag during restoring", .tags(.unit))
    func testOperationalFlagDuringRestoring() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        await session.updateStateForTesting(to: .restoring)
        
        #expect(await session.isOperational)
        #expect(await session.isRunning == false)
    }
    
    // MARK: - Start/Stop and events
    
    @Test("starting and stopping emits lifecycle events", .tags(.integration))
    func testStartAndStopSessionEmitsLifecycleEvents() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress,
                                                       configuration: .init())
        defer { Task { await session.stopIfRunningForTesting() } }
        
        let eventBox = EventIteratorBox(await session.makeEventStream().makeAsyncIterator())
        
        try await session.start()
        
        let firstEvent = try await Self.waitForEvent(eventBox)
        #expect(firstEvent == .didPromoteServer(Self.healthyServerAddress))
        
        let secondEvent = try await Self.waitForEvent(eventBox)
        #expect(secondEvent == .didActivateServer(Self.healthyServerAddress))
        
        #expect(await session.state == .running)
        #expect(await session.isRunning)
        #expect(await session.isOperational)
        
        try await session.stop()
        
        let thirdEvent = try await Self.waitForEvent(eventBox)
        #expect(thirdEvent == .didDeactivateServer(Self.healthyServerAddress))
        #expect(await session.state == .stopped)
        #expect(await session.isRunning == false)
        #expect(await session.isOperational == false)
        #expect(await session.activeServerAddress == nil)
    }
    
    @Test("event streams broadcast to multiple observers", .tags(.integration))
    func testEventStreamBroadcastToMultipleObservers() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { await session.stopIfRunningForTesting() } }
        
        // Support optional or non-optional return types.
        let stream1Opt: AsyncStream<Network.FulcrumSession.Event>? = await session.makeEventStream()
        let stream2Opt: AsyncStream<Network.FulcrumSession.Event>? = await session.makeEventStream()
        
        guard let stream1 = stream1Opt, let stream2 = stream2Opt else {
            #expect(Bool(false), "Expected to receive event streams for observers")
            return
        }
        
        let box1 = EventIteratorBox(stream1.makeAsyncIterator())
        let box2 = EventIteratorBox(stream2.makeAsyncIterator())
        
        try await session.start()
        
        let ev1 = try await Self.waitForEvent(box1)
        let ev2 = try await Self.waitForEvent(box2)
        
        #expect(ev1 == .didPromoteServer(Self.healthyServerAddress))
        #expect(ev2 == .didPromoteServer(Self.healthyServerAddress))
    }
    
    @Test("starting an already running session throws", .tags(.integration))
    func testStartTwiceThrows() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress,
                                                       configuration: .init())
        defer { Task { await session.stopIfRunningForTesting() } }
        
        try await session.start()
        #expect(await session.state == .running)
        
        await #expect(throws: Network.FulcrumSession.Error.sessionAlreadyStarted) {
            try await session.start()
        }
        
        try await session.stop()
        #expect(await session.state == .stopped)
    }
    
    @Test("stopping a session that never started throws", .tags(.unit))
    func testStopWhenNotRunningThrows() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            try await session.stop()
        }
    }
    
    @Test("connection failures emit demotion and failure events", .tags(.integration))
    func testStartWithUnavailableServerEmitsFailureEvents() async throws {
        let unavailableServer = URL(string: "ws://127.0.0.1:1")!
        let configuration = SwiftFulcrum.Fulcrum.Configuration(connectionTimeout: 1,
                                                               bootstrapServers: nil)
        let session = try await Network.FulcrumSession(serverAddress: unavailableServer,
                                                       configuration: configuration)
        
        let eventBox = EventIteratorBox(await session.makeEventStream().makeAsyncIterator())
        
        do {
            try await session.start()
            Issue.record("Expected start to fail for unavailable server")
        } catch {
            let failureEvent = try await Self.waitForEvent(eventBox)
            switch failureEvent {
            case let .didFailToConnectToServer(server, failureDescription: description):
                #expect(server == unavailableServer)
                #expect(description.isEmpty == false)
            default:
                Issue.record("Unexpected event: \(failureEvent)")
            }
            
            let demotionEvent = try await Self.waitForEvent(eventBox)
            #expect(demotionEvent == .didDemoteServer(unavailableServer))
            #expect(await session.state == .stopped)
        }
    }
    
    @Test("starting against unreachable server leaves session stopped", .tags(.unit))
    func testStartFailsForUnreachableServer() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.unreachableServerAddress)
        
        do {
            try await session.start()
            #expect(Bool(false), "Expected connection failure for unreachable server")
        } catch {
            switch error {
            case is SwiftFulcrum.Fulcrum.Error:
                break
            default:
                #expect(Bool(false), "Unexpected error type: \(error)")
            }
        }
        
        #expect(await session.state == .stopped)
        #expect(await session.isRunning == false)
        #expect(await session.isOperational == false)
        #expect(await session.activeServerAddress == nil)
    }
    
    @Test("reconnect without active fulcrum resets session to stopped", .tags(.unit))
    func testReconnectWithoutActiveFulcrumResetsState() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        
        await session.updateStateForTesting(to: .running)
        
        do {
            try await session.reconnect()
            #expect(Bool(false), "Expected sessionNotStarted when reconnecting without fulcrum")
        } catch {
            switch error {
            case Network.FulcrumSession.Error.sessionNotStarted:
                break
            default:
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
        
        #expect(await session.state == .stopped)
        #expect(await session.isRunning == false)
        #expect(await session.isOperational == false)
    }
    
    // MARK: - Candidate server discovery
    
    @Test("initialising a session prepares candidate servers", .tags(.unit))
    func testInitializeSessionStatePreparesCandidateServers() async throws {
        let duplicateServer = Self.healthyServerAddress
        let additionalServerOne = URL(string: "wss://example.fulcrum.one:50004")!
        let additionalServerTwo = URL(string: "wss://example.fulcrum.two:50006")!
        let invalidServer = URL(string: "https://invalid.fulcrum:50004")!
        
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: [
            duplicateServer,
            additionalServerOne,
            additionalServerTwo,
            invalidServer
        ])
        
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress,
                                                       configuration: configuration)
        
        #expect(await session.state == .stopped)
        #expect(await session.isRunning == false)
        #expect(await session.isOperational == false)
        #expect(await session.preferredServerAddress == Self.healthyServerAddress)
        
        let candidateServers = await session.candidateServerAddresses
        #expect(candidateServers == [
            Self.healthyServerAddress,
            additionalServerOne,
            additionalServerTwo
        ])
    }
    
    @Test("candidate discovery filters unsupported URLs", .tags(.unit))
    func testMakeCandidateServerAddressesFiltersUnsupportedURLs() {
        let preferredServer: URL? = nil
        let websocketServer = URL(string: "ws://127.0.0.1:60000")!
        let secureServer = URL(string: "wss://example.secure.fulcrum:50004")!
        let invalidScheme = URL(string: "ftp://example.fulcrum:21")!
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: [
            websocketServer, secureServer, invalidScheme
        ])
        
        let candidates = Network.FulcrumSession.makeCandidateServerAddresses(
            from: preferredServer,
            configuration: configuration
        )
        #expect(candidates == [websocketServer, secureServer])
    }
    
    @Test("candidate discovery prioritises preferred and deduplicates; filters unsupported", .tags(.unit))
    func testMakeCandidateServerAddressesDeduplicatesAndFilters() {
        let primaryServer = URL(string: "wss://primary.wallet.example")!
        let uppercaseDuplicate = URL(string: "WSS://PRIMARY.WALLET.EXAMPLE")!
        let backupServer = URL(string: "ws://backup.wallet.example")!
        let invalidServer = URL(string: "https://insecure.wallet.example")!
        
        let configuration = SwiftFulcrum.Fulcrum.Configuration(
            bootstrapServers: [uppercaseDuplicate, backupServer, invalidServer]
        )
        
        let candidates = Network.FulcrumSession.makeCandidateServerAddresses(
            from: primaryServer,
            configuration: configuration
        )
        
        #expect(candidates.first == primaryServer)
        #expect(candidates.contains(backupServer))
        #expect(candidates.contains { $0.scheme?.lowercased() == "https" } == false)
        #expect(candidates.filter { $0 == primaryServer }.count == 1)
        #expect(candidates.count == 2)
    }
    
    @Test("candidate discovery falls back to bundled endpoints when needed", .tags(.unit))
    func testMakeCandidateServerAddressesFallsBackToBundledServers() {
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: nil)
        
        let candidates = Network.FulcrumSession.makeCandidateServerAddresses(
            from: nil,
            configuration: configuration
        )
        
        #expect(candidates.isEmpty == false)
        for candidate in candidates {
            #expect(["ws", "wss"].contains(candidate.scheme?.lowercased()))
        }
    }
    
    // MARK: - Server activation errors
    
    @Test("activating an unsupported server reverts state", .tags(.unit))
    func testActivateUnsupportedServerThrowsAndReverts() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress,
                                                       configuration: .init())
        let unsupportedServer = URL(string: "http://unsupported.fulcrum.server:50004")!
        let initialPreferred = await session.preferredServerAddress
        let initialCandidates = await session.candidateServerAddresses
        
        await #expect(throws: Network.FulcrumSession.Error.unsupportedServerAddress) {
            try await session.activateServerAddress(unsupportedServer)
        }
        
        #expect(await session.preferredServerAddress == initialPreferred)
        #expect(await session.candidateServerAddresses == initialCandidates)
    }
    
    // MARK: - Helpers
    
    private static func waitForEvent(
        _ box: EventIteratorBox,
        timeout: Duration = eventTimeout
    ) async throws -> Network.FulcrumSession.Event {
        try await withThrowingTaskGroup(of: Network.FulcrumSession.Event?.self) { group in
            group.addTask { await box.next() }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            
            guard let event = try await group.next() ?? nil else {
                group.cancelAll()
                throw TestError.timedOutWaitingForEvent
            }
            
            group.cancelAll()
            return event
        }
    }
}

private actor EventIteratorBox {
    private var iterator: AsyncStream<Network.FulcrumSession.Event>.Iterator
    init(_ iterator: AsyncStream<Network.FulcrumSession.Event>.Iterator) {
        self.iterator = iterator
    }
    func next() async -> Network.FulcrumSession.Event? {
        return await iterator.next()
    }
}

private extension Network.FulcrumSession {
    func setStateForTesting(_ newState: State) async {
        state = newState
    }
    
    func updateStateForTesting(_ newState: State) {
        state = newState
    }
    
    func updateStateForTesting(to newState: State) async {
        state = newState
    }
    
    func stopIfRunningForTesting() async {
        guard isRunning else { return }
        do {
            try await stop()
        } catch {
            Issue.record("Failed to stop session during cleanup: \(error)")
        }
    }
}
