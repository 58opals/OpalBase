import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession Connection", .tags(.network, .integration))
struct NetworkFulcrumSessionConnectionTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let unreachableServerAddress = URL(string: "ws://127.0.0.1:65535")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    @Test("start activates preferred server and emits lifecycle events", .timeLimit(.minutes(1)))
    func testStartActivatesPreferredServer() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        var events = await session.makeEventStream().makeAsyncIterator()
        
        try await session.start()
        
        #expect(await session.state == .running)
        #expect(await session.activeServerAddress == Self.healthyServerAddress)
        #expect(await session.isOperational)
        
        var didActivateServer = false
        var didStart = false
        
        for _ in 0..<6 {
            guard let event = await events.next() else { break }
            
            switch event {
            case .didActivateServer(let url) where url == Self.healthyServerAddress:
                didActivateServer = true
            case .didStart(let url) where url == Self.healthyServerAddress:
                didStart = true
            default:
                continue
            }
            
            if didActivateServer && didStart { break }
        }
        
        #expect(didActivateServer)
        #expect(didStart)
    }
    
    @Test("stop terminates active connection and clears active server", .timeLimit(.minutes(1)))
    func testStopTerminatesConnection() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        var events = await session.makeEventStream().makeAsyncIterator()
        
        try await session.start()
        
        for _ in 0..<6 {
            guard let event = await events.next() else { break }
            if case .didStart = event { break }
        }
        
        try await session.stop()
        
        var didDeactivateServer = false
        for _ in 0..<4 {
            guard let event = await events.next() else { break }
            if case .didDeactivateServer(let url) = event, url == Self.healthyServerAddress {
                didDeactivateServer = true
                break
            }
        }
        
        #expect(didDeactivateServer)
        #expect(await session.state == .stopped)
        #expect(await session.activeServerAddress == nil)
    }
    
    @Test("reconnect keeps the active server and preserves request capabilities", .timeLimit(.minutes(1)))
    func testReconnectMaintainsActiveServer() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        var events = await session.makeEventStream().makeAsyncIterator()
        
        try await session.start()
        
        for _ in 0..<6 {
            guard let event = await events.next() else { break }
            if case .didStart = event { break }
        }
        
        let initialBalance = try await session.fetchAddressBalance(Self.sampleAddress)
        let activeServerBeforeReconnect = await session.activeServerAddress
        
        try await session.reconnect()
        
        var didReconnect = false
        for _ in 0..<4 {
            guard let event = await events.next() else { break }
            if case .didReconnect(let url) = event, url == activeServerBeforeReconnect {
                didReconnect = true
                break
            }
        }
        
        let balanceAfterReconnect = try await session.fetchAddressBalance(Self.sampleAddress)
        
        #expect(didReconnect)
        #expect(await session.activeServerAddress == activeServerBeforeReconnect)
        #expect(balanceAfterReconnect.confirmed >= 0)
        #expect(initialBalance.confirmed >= 0)
    }
    
    @Test("start falls back when the preferred server fails", .timeLimit(.minutes(1)))
    func testStartFallsBackToBootstrapServer() async throws {
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: [Self.healthyServerAddress])
        let session = try await Network.FulcrumSession(serverAddress: Self.unreachableServerAddress,
                                                       configuration: configuration)
        defer { Task { try? await session.stop() } }
        
        var events = await session.makeEventStream().makeAsyncIterator()
        
        try await session.start()
        
        #expect(await session.state == .running)
        #expect(await session.activeServerAddress == Self.healthyServerAddress)
        
        var didFailToConnect = false
        var didFallback = false
        var didActivateHealthy = false
        
        for _ in 0..<12 {
            guard let event = await events.next() else { break }
            switch event {
            case .didFailToConnectToServer(let url, _) where url == Self.unreachableServerAddress:
                didFailToConnect = true
            case .didFallback(let origin, let destination)
                where origin == Self.unreachableServerAddress && destination == Self.healthyServerAddress:
                didFallback = true
            case .didActivateServer(let url) where url == Self.healthyServerAddress:
                didActivateHealthy = true
            case .didStart(let url) where url == Self.healthyServerAddress:
                didActivateHealthy = true
            default:
                continue
            }
            
            if didFailToConnect && didFallback && didActivateHealthy { break }
        }
        
        #expect(didFailToConnect)
        #expect(didFallback)
        #expect(didActivateHealthy)
    }
    
    @Test("start while running throws sessionAlreadyStarted", .timeLimit(.minutes(1)))
    func testStartThrowsWhenAlreadyRunning() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        #expect(await session.state == .running)
        
        await #expect(throws: Network.FulcrumSession.Error.sessionAlreadyStarted) {
            try await session.start()
        }
    }
    
    @Test("activateServerAddress rejects unsupported scheme", .timeLimit(.minutes(1)))
    func testActivateServerAddressRejectsUnsupportedScheme() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let previousPreferred = await session.preferredServerAddress
        let previousCandidates = await session.candidateServerAddresses
        
        await #expect(throws: Network.FulcrumSession.Error.unsupportedServerAddress) {
            try await session.activateServerAddress(URL(string: "https://example.com")!)
        }
        
        #expect(await session.preferredServerAddress == previousPreferred)
        #expect(await session.candidateServerAddresses == previousCandidates)
        #expect(await session.activeServerAddress == previousPreferred)
        #expect(await session.state == .running)
    }
}
