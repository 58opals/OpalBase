import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession", .tags(.network))
struct NetworkFulcrumSessionTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    
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
            try await session.start()
            #expect(await session.isRunning)
            
            print(await session.isRunning)
            try await session.reconnect()
            print(await session.isRunning)
            
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
    
    private func withSession(
        using serverAddress: URL = Self.healthyServerAddress,
        configuration: SwiftFulcrum.Fulcrum.Configuration = .init(),
        perform: @escaping @Sendable (Network.FulcrumSession) async throws -> Void
    ) async throws {
        let session = try await Network.FulcrumSession(serverAddress: serverAddress, configuration: configuration)
        
        do {
            try await perform(session)
        } catch {
            await session.stop()
            #expect(await !session.isRunning)
            throw error
        }
        
        await session.stop()
        #expect(await !session.isRunning)
    }
}
