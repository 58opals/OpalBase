import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession", .tags(.network))
struct NetworkFulcrumSessionTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    
    private func collectEvents(
        from stream: AsyncStream<Network.FulcrumSession.Event>,
        until condition: @escaping ([Network.FulcrumSession.Event]) -> Bool
    ) async -> [Network.FulcrumSession.Event] {
        var events: [Network.FulcrumSession.Event] = []
        var iterator = stream.makeAsyncIterator()
        
        while let event = await iterator.next() {
            events.append(event)
            
            if condition(events) || events.count >= 50 {
                break
            }
        }
        
        return events
    }
    
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

extension NetworkFulcrumSessionTests {
    @Test("candidate server addresses surface the configured candidates", .tags(.unit))
    func testCandidateServerAddressesExposeConfiguration() async throws {
        let preferredServerAddress = URL(string: "wss://fulcrum.example.opalbase.test:50004")!
        let bootstrapServerAddress = URL(string: "wss://fulcrum.bootstrap.opalbase.test:50004")!
        let configuration = SwiftFulcrum.Fulcrum.Configuration(bootstrapServers: [bootstrapServerAddress])
        
        try await withSession(using: preferredServerAddress, configuration: configuration) { session in
            let addresses = await session.candidateServerAddresses
            
            #expect(addresses.contains(preferredServerAddress))
            #expect(addresses.contains(bootstrapServerAddress))
        }
    }
    
    @Test("activate server validates unsupported schemes", .tags(.unit))
    func testActivateServerValidatesSchemes() async throws {
        let unsupportedServerAddress = URL(string: "http://example.com")!
        
        try await withSession { session in
            do {
                try await session.activateServerAddress(unsupportedServerAddress)
                #expect(Bool(false), "Expected activateServerAddress to throw for unsupported schemes")
            } catch let sessionError as Network.FulcrumSession.Error {
                guard case .unsupportedServerAddress = sessionError else {
                    return #expect(Bool(false), "Unexpected session error: \(sessionError)")
                }
            } catch {
                #expect(Bool(false), "Unexpected error: \(error)")
            }
            
            let addresses = await session.candidateServerAddresses
            #expect(!addresses.contains(unsupportedServerAddress))
        }
    }
    
    @Test("event stream surfaces failover activity", .tags(.integration))
    func testEventStreamSurfacesFailoverActivity() async throws {
        let unreachableServer = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
        let configuration = SwiftFulcrum.Fulcrum.Configuration(
            connectionTimeout: 1,
            bootstrapServers: [Self.healthyServerAddress]
        )
        
        try await withSession(using: unreachableServer, configuration: configuration) { session in
            let eventStream = await session.makeEventStream()
            
            async let observedEvents = collectEvents(from: eventStream) { events in
                let hasFailure = events.contains { event in
                    if case .didFailToConnectToServer(unreachableServer, _) = event { return true }
                    return false
                }
                
                let hasDemotion = events.contains { event in
                    if case .didDemoteServer(unreachableServer) = event { return true }
                    return false
                }
                
                let hasPromotion = events.contains { event in
                    if case .didPromoteServer(Self.healthyServerAddress) = event { return true }
                    return false
                }
                
                let hasActivation = events.contains { event in
                    if case .didActivateServer(Self.healthyServerAddress) = event { return true }
                    return false
                }
                
                return hasFailure && hasDemotion && hasPromotion && hasActivation
            }
            
            try await session.start()
            
            let events = await observedEvents
            
            #expect(events.contains { event in
                if case .didFailToConnectToServer(unreachableServer, _) = event { return true }
                return false
            })
            
            #expect(events.contains { event in
                if case .didDemoteServer(unreachableServer) = event { return true }
                return false
            })
            
            #expect(events.contains { event in
                if case .didPromoteServer(Self.healthyServerAddress) = event { return true }
                return false
            })
            
            #expect(events.contains { event in
                if case .didActivateServer(Self.healthyServerAddress) = event { return true }
                return false
            })
        }
    }
    
    @Test("start, fetch header tip, and stop on a healthy server", .tags(.integration))
    func testStartFetchTipAndStopOnHealthyServer() async throws {
        try await withSession { session in
            try await session.start()
            #expect(await session.isRunning)
            
            let response = try await session.submit(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            
            guard case .single(_, let tip) = response else {
                return #expect(Bool(false), "Expected a single response when requesting the header tip")
            }
            
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
        }
    }
    
    @Test("reconnect keeps the session healthy", .tags(.integration))
    func testReconnectKeepsSessionHealthy() async throws {
        try await withSession { session in
            try await session.start()
            #expect(await session.isRunning)
            
            try await session.reconnect()
            
            let response = try await session.submit(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            
            guard case .single(_, let tip) = response else {
                return #expect(Bool(false), "Expected a single response when requesting the header tip after reconnecting")
            }
            
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
            #expect(await session.isRunning)
        }
    }
    
    @Test("start falls back to a healthy server when the primary endpoint fails", .tags(.integration))
    func testStartFallsBackToHealthyServer() async throws {
        let unreachableServer = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
        let configuration = SwiftFulcrum.Fulcrum.Configuration(
            connectionTimeout: 1,
            bootstrapServers: [Self.healthyServerAddress]
        )
        
        try await withSession(using: unreachableServer, configuration: configuration) { session in
            try await session.start()
            #expect(await session.isRunning)
            
            let response = try await session.submit(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            
            guard case .single(_, let tip) = response else {
                return #expect(Bool(false), "Expected a single response when requesting the header tip after failing over")
            }
            
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
        }
    }
    
    @Test("submit requires the session to be running", .tags(.unit))
    func testSubmitRequiresRunningSession() async throws {
        try await withSession { session in
            #expect(await !session.isRunning)
            
            do {
                _ = try await session.submit(
                    method: .blockchain(.headers(.getTip)),
                    responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
                )
                #expect(Bool(false), "Expected submit to throw when the session has not been started")
            } catch let sessionError as Network.FulcrumSession.Error {
                guard case .sessionNotStarted = sessionError else {
                    return #expect(Bool(false), "Unexpected session error: \(sessionError)")
                }
            } catch {
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
    }
    
    @Test("reconnect requires the session to be running", .tags(.unit))
    func testReconnectRequiresRunningSession() async throws {
        try await withSession { session in
            #expect(await !session.isRunning)
            
            do {
                try await session.reconnect()
                #expect(Bool(false), "Expected reconnect to throw when the session has not been started")
            } catch let sessionError as Network.FulcrumSession.Error {
                guard case .sessionNotStarted = sessionError else {
                    return #expect(Bool(false), "Unexpected session error: \(sessionError)")
                }
            } catch {
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
    }
    
    @Test("start requires the session to be idle", .tags(.unit))
    func testStartRequiresIdleSession() async throws {
        try await withSession { session in
            try await session.start()
            
            do {
                try await session.start()
                #expect(Bool(false), "Expected start to throw when the session is already running")
            } catch let sessionError as Network.FulcrumSession.Error {
                guard case .sessionAlreadyStarted = sessionError else {
                    return #expect(Bool(false), "Unexpected session error: \(sessionError)")
                }
            } catch {
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
    }
    
    @Test("stop requires the session to be running", .tags(.unit))
    func testStopRequiresRunningSession() async throws {
        try await withSession { session in
            #expect(await !session.isRunning)
            
            do {
                try await session.stop()
                #expect(Bool(false), "Expected stop to throw when the session has not been started")
            } catch let sessionError as Network.FulcrumSession.Error {
                guard case .sessionNotStarted = sessionError else {
                    return #expect(Bool(false), "Unexpected session error: \(sessionError)")
                }
            } catch {
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
    }
    
    @Test("start fails fast for unreachable servers", .tags(.integration))
    func testStartFailsFastForUnreachableServers() async throws {
        let unreachableServer = URL(string: "wss://unreachable.fulcrum.opalbase.test:12345")!
        let configuration = SwiftFulcrum.Fulcrum.Configuration(connectionTimeout: 1)
        
        try await withSession(using: unreachableServer, configuration: configuration) { session in
            #expect(await !session.isRunning)
            
            do {
                try await session.start()
                #expect(Bool(false), "Expected start to throw for an unreachable server")
            } catch {
                #expect(await !session.isRunning)
            }
        }
    }
}
