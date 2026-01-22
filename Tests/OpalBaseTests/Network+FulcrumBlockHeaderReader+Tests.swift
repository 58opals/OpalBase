import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumBlockHeaderReader", .tags(.network))
struct NetworkFulcrumBlockHeaderReaderTests {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let faultyServerAddress = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    private static let invalidServerAddress = URL(string: "not a url")!
    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let invalidCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
    
    @Test("fetches tip snapshot consistent with fulcrum RPC", .timeLimit(.minutes(1)))
    func testFetchTipMatchesServerResponse1() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumBlockHeaderReader(client: client)
            let rpcTip: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            
            let snapshot = try await reader.fetchTip()
            
            #expect(snapshot.height >= rpcTip.height)
            #expect(!snapshot.headerHexadecimal.isEmpty)
            #expect(snapshot.headerHexadecimal.count == rpcTip.hex.count)
        }
    }
    
    @Test("fetches the current block tip and mirrors raw headers response", .timeLimit(.minutes(1)))
    func testFetchTipMatchesServerResponse2() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumBlockHeaderReader(client: client)
            let snapshot = try await reader.fetchTip()
            #expect(snapshot.height >= 0)
            #expect(snapshot.headerHexadecimal.count == 160)
            
            let rpcTip: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            
            #expect(rpcTip.height == snapshot.height)
            #expect(rpcTip.hex == snapshot.headerHexadecimal)
        }
    }
    
    @Test("fetches the live tip for wallet sync", .timeLimit(.minutes(1)))
    func testFetchTipProvidesCurrentSnapshot() async throws {
        let configuration = Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectionTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 3,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumBlockHeaderReader(client: client)
            let baseline: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(.headers(.getTip)),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip.self
            )
            
            let snapshot = try await reader.fetchTip()
            #expect(snapshot.height >= baseline.height)
            #expect(!snapshot.headerHexadecimal.isEmpty)
            
            if snapshot.height == baseline.height {
                #expect(snapshot.headerHexadecimal == baseline.hex)
            }
        }
    }
    
    @Test("falls back to the next available server when the first endpoint fails", .timeLimit(.minutes(1)))
    func testFetchTipWithServerFailover() async throws {
        let configuration = Network.Configuration(
            serverURLs: [Self.faultyServerAddress, Self.primaryServerAddress, Self.backupServerAddress],
            connectionTimeout: .seconds(8),
            reconnect: .init(maximumAttempts: 3, initialDelay: .seconds(1), maximumDelay: .seconds(5),  jitterMultiplierRange: 0.9 ... 1.2)
        )
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumBlockHeaderReader(client: client)
            let snapshot = try await reader.fetchTip()
            #expect(snapshot.height > 0)
            #expect(snapshot.headerHexadecimal.count == 160)
        }
    }
    
    @Test("streams live headers and surfaces disconnects", .timeLimit(.minutes(1)))
    func testSubscribeToTipDeliversSnapshotsAndErrors() async throws {
        let configuration = Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectionTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 3,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumBlockHeaderReader(client: client)
            let stream = try await reader.subscribeToTip()
            var iterator = stream.makeAsyncIterator()
            
            guard let initialSnapshot = try await iterator.next() else {
                Issue.record("Expected an initial snapshot before the stream ended")
                return
            }
            
            #expect(initialSnapshot.height > 0)
            #expect(!initialSnapshot.headerHexadecimal.isEmpty)
            
            async let followUp = iterator.next()
            try await Task.sleep(for: .seconds(1))
            await client.stop()
            
            do {
                if let nextSnapshot = try await followUp {
                    #expect(nextSnapshot.height >= initialSnapshot.height)
                    #expect(!nextSnapshot.headerHexadecimal.isEmpty)
                } else {
                    #expect(true, "Stream ended cleanly after client stop")
                }
            } catch let failure as Network.Failure {
                #expect(!(failure.message == nil) || failure.reason == .cancelled)
            }
        }
    }
}
