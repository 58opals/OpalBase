import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession State", .tags(.network, .integration))
struct NetworkFulcrumSessionStateTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let unreachableServerAddress = URL(string: "ws://127.0.0.1:65535")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    @Test("start records fallback transition and clears pending origin", .timeLimit(.minutes(1)))
    func testStartRecordsFallbackTransition() async throws {
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: [Self.healthyServerAddress])
        let session = try await Network.FulcrumSession(serverAddress: Self.unreachableServerAddress,
                                                       configuration: configuration)
        defer { Task { try? await session.stop() } }
        
        var events = await session.makeEventStream().makeAsyncIterator()
        
        try await session.start()
        
        #expect(await session.state == .running)
        #expect(await session.activeServerAddress == Self.healthyServerAddress)
        #expect(await session.pendingFallbackOrigin == nil)
        
        var didFallback = false
        var didStart = false
        
        for _ in 0..<12 {
            guard let event = await events.next() else { break }
            switch event {
            case .didFallback(let origin, let destination)
                where origin == Self.unreachableServerAddress && destination == Self.healthyServerAddress:
                didFallback = true
            case .didStart(let url) where url == Self.healthyServerAddress:
                didStart = true
            default:
                continue
            }
            
            if didFallback && didStart { break }
        }
        
        #expect(didFallback)
        #expect(didStart)
    }
    
    @Test("reconnect emits reconnect event and maintains operational state", .timeLimit(.minutes(1)))
    func testReconnectRecordsReconnectEvent() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        var events = await session.makeEventStream().makeAsyncIterator()
        
        try await session.start()
        
        var didStart = false
        for _ in 0..<6 {
            guard let event = await events.next() else { break }
            if case .didStart(let url) = event, url == Self.healthyServerAddress {
                didStart = true
                break
            }
        }
        
        #expect(didStart)
        #expect(await session.pendingFallbackOrigin == nil)
        
        let balanceBeforeReconnect = try await session.fetchAddressBalance(Self.sampleAddress)
        let activeServerBeforeReconnect = await session.activeServerAddress
        
        try await session.reconnect()
        
        var didReconnect = false
        for _ in 0..<6 {
            guard let event = await events.next() else { break }
            switch event {
            case .didReconnect(let url) where url == activeServerBeforeReconnect:
                didReconnect = true
            case .didFallback:
                #expect(Bool(false), "Unexpected fallback emitted during reconnect")
            default:
                continue
            }
            
            if didReconnect { break }
        }
        
        let balanceAfterReconnect = try await session.fetchAddressBalance(Self.sampleAddress)
        
        #expect(didReconnect)
        #expect(await session.activeServerAddress == activeServerBeforeReconnect)
        #expect(balanceBeforeReconnect.confirmed >= 0)
        #expect(balanceAfterReconnect.confirmed >= 0)
        #expect(await session.pendingFallbackOrigin == nil)
    }
    
    @Test("fallback emits origin and destination transition", .timeLimit(.minutes(1)))
    func testFallbackRecordsOriginAndDestination() async throws {
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: [Self.healthyServerAddress])
        let session = try await Network.FulcrumSession(serverAddress: Self.unreachableServerAddress,
                                                       configuration: configuration)
        defer { Task { try? await session.stop() } }
        
        var events = await session.makeEventStream().makeAsyncIterator()
        
        #expect(await session.pendingFallbackOrigin == nil)
        
        try await session.start()
        
        #expect(await session.state == .running)
        #expect(await session.activeServerAddress == Self.healthyServerAddress)
        
        var didFailToConnect = false
        var didFallback = false
        var didStart = false
        
        for _ in 0..<20 {
            guard let event = await events.next() else { break }
            switch event {
            case .didFailToConnectToServer(let url, _) where url == Self.unreachableServerAddress:
                didFailToConnect = true
            case .didFallback(let origin, let destination)
                where origin == Self.unreachableServerAddress && destination == Self.healthyServerAddress:
                didFallback = true
            case .didStart(let url) where url == Self.healthyServerAddress:
                didStart = true
            default:
                continue
            }
            
            if didFailToConnect && didFallback && didStart { break }
        }
        
        #expect(didFailToConnect)
        #expect(didFallback)
        #expect(didStart)
        #expect(await session.pendingFallbackOrigin == nil)
    }
}
