import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession Connection", .tags(.network, .integration))
struct NetworkFulcrumSessionConnectionTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let failingServerAddress = URL(string: "wss://127.0.0.1:65535")!
    private static let unsupportedServerAddress = URL(string: "http://example.com")!

    // MARK: Start / Stop

    @Test("start activates the preferred server and transitions to running")
    func startActivatesPreferredServer() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { await session.stopIfOperationalForTesting() } }

        var iterator = await session.makeEventStream().makeAsyncIterator()

        try await session.start()

        let activation = try await Self.waitForEvent(in: &iterator) { event in
            guard case .didActivateServer(let address) = event else { return false }
            return address == Self.healthyServerAddress
        }

        #expect(activation == .didActivateServer(Self.healthyServerAddress))
        #expect(await session.state == .running)
        #expect(await session.activeServerAddress == Self.healthyServerAddress)
    }

    @Test("stop emits deactivation and resets state")
    func stopResetsState() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)

        var iterator = await session.makeEventStream().makeAsyncIterator()

        try await session.start()
        _ = try await Self.waitForEvent(in: &iterator) { event in
            guard case .didActivateServer(let address) = event else { return false }
            return address == Self.healthyServerAddress
        }

        try await session.stop()

        let deactivation = try await Self.waitForEvent(in: &iterator) { event in
            guard case .didDeactivateServer(let address) = event else { return false }
            return address == Self.healthyServerAddress
        }

        #expect(deactivation == .didDeactivateServer(Self.healthyServerAddress))
        #expect(await session.state == .stopped)
        #expect(await session.activeServerAddress == nil)
    }

    @Test("start rejects duplicate calls while running")
    func startRejectsDuplicateCalls() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { await session.stopIfOperationalForTesting() } }

        try await session.start()

        await #expect(throws: Network.FulcrumSession.Error.sessionAlreadyStarted) {
            try await session.start()
        }
    }

    // MARK: Reconnect

    @Test("reconnect rejects calls when the session is idle")
    func reconnectWhenIdleThrows() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)

        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            try await session.reconnect()
        }
    }

    @Test("reconnect keeps an established session running")
    func reconnectKeepsSessionRunning() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { await session.stopIfOperationalForTesting() } }

        try await session.start()
        try await session.reconnect()

        #expect(await session.state == .running)
        #expect(await session.activeServerAddress == Self.healthyServerAddress)
    }

    // MARK: Activate Server

    @Test("activateServerAddress rejects unsupported addresses and preserves preference")
    func activateServerRejectsUnsupportedAddress() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { await session.stopIfOperationalForTesting() } }

        try await session.start()

        let originalPreferred = await session.preferredServerAddress
        let originalActive = await session.activeServerAddress

        await #expect(throws: Network.FulcrumSession.Error.unsupportedServerAddress) {
            try await session.activateServerAddress(Self.unsupportedServerAddress)
        }

        #expect(await session.preferredServerAddress == originalPreferred)
        #expect(await session.activeServerAddress == originalActive)
    }

    @Test("activating an unsupported server while stopped preserves configuration")
    func activateUnsupportedWhenStoppedPreservesConfiguration() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)

        let previousPreferred = await session.preferredServerAddress
        let previousCandidates = await session.candidateServerAddresses

        await #expect(throws: Network.FulcrumSession.Error.unsupportedServerAddress) {
            try await session.activateServerAddress(Self.unsupportedServerAddress)
        }

        #expect(await session.preferredServerAddress == previousPreferred)
        #expect(await session.candidateServerAddresses == previousCandidates)
        #expect(await session.state == .stopped)
        #expect(await session.activeServerAddress == nil)
    }

    // MARK: Fallback / Failure

    @Test("start falls back to a healthy candidate after a connection failure")
    func startFallsBackToHealthyCandidate() async throws {
        let configuration = SwiftFulcrum.Fulcrum.Configuration(connectionTimeout: 2,
                                                               bootstrapServers: [Self.failingServerAddress,
                                                                                 Self.healthyServerAddress])
        let session = try await Network.FulcrumSession(serverAddress: nil, configuration: configuration)
        defer { Task { await session.stopIfOperationalForTesting() } }

        let eventTask = Task { () -> [Network.FulcrumSession.Event] in
            let stream = await session.makeEventStream()
            var iterator = stream.makeAsyncIterator()
            var events: [Network.FulcrumSession.Event] = []

            while let event = await iterator.next() {
                events.append(event)
                if case .didActivateServer(Self.healthyServerAddress) = event { break }
                if events.count >= 8 { break }
            }

            return events
        }

        try await session.start()

        let events = await eventTask.value
        let activeServer = await session.activeServerAddress
        let candidates = await session.candidateServerAddresses

        #expect(activeServer == Self.healthyServerAddress)
        #expect(candidates.first == Self.healthyServerAddress)
        #expect(candidates.last == Self.failingServerAddress)
        #expect(events.contains { if case .didFailToConnectToServer(Self.failingServerAddress, _) = $0 { return true } else { return false } })
        #expect(events.contains { if case .didActivateServer(Self.healthyServerAddress) = $0 { return true } else { return false } })
    }

    @Test("start emits a failure when no servers are reachable")
    func startFailsWhenNoServersReachable() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.failingServerAddress)
        var iterator = await session.makeEventStream().makeAsyncIterator()

        do {
            try await session.start()
            Issue.record("Expected start to fail for unreachable server")
        } catch { }

        let failure = try await Self.waitForEvent(in: &iterator) { event in
            if case .didFailToConnectToServer(Self.failingServerAddress, _) = event { return true }
            return false
        }

        #expect({
            if case .didFailToConnectToServer(Self.failingServerAddress, _) = failure { return true }
            return false
        }())
        #expect(await session.state == .stopped)
        #expect(await session.activeServerAddress == nil)
    }

    // MARK: Stop validation

    @Test("stop rejects calls when the session is idle")
    func stopWhenIdleThrows() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)

        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            try await session.stop()
        }
    }
}

// MARK: - Test Utilities

private extension NetworkFulcrumSessionConnectionTests {
    static func waitForEvent(
        in iterator: inout AsyncStream<Network.FulcrumSession.Event>.Iterator,
        matching predicate: (Network.FulcrumSession.Event) -> Bool
    ) async throws -> Network.FulcrumSession.Event {
        while let event = await iterator.next() {
            if predicate(event) { return event }
        }
        throw WaitError.streamEnded
    }

    private enum WaitError: Swift.Error {
        case streamEnded
    }
}

private extension Network.FulcrumSession {
    func stopIfOperationalForTesting() async {
        if state == .running {
            try? await stop()
        }
    }
}
