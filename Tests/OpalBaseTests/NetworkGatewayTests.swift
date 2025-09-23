import Foundation
import Testing
@testable import OpalBase

@Suite("Network Gateway")
struct NetworkGatewayTests {
    @Test func testBroadcastIsIdempotent() async throws {
        let client = MockGatewayClient()
        let configuration = Network.Gateway.Configuration(initialStatus: .online,
                                                          initialHeaderUpdate: Date())
        let gateway = Network.Gateway(client: client, configuration: configuration)
        let transaction = Self.sampleTransaction(seed: 0x01)
        let acknowledged = Transaction.Hash(naturalOrder: Data(repeating: 0x42, count: 32))
        
        client.broadcastHandler = { _ in acknowledged }
        client.fetchHandler = { _ in nil }
        
        let first = try await gateway.broadcast(transaction)
        let second = try await gateway.broadcast(transaction)
        
        #expect(first == acknowledged)
        #expect(second == acknowledged)
        #expect(client.broadcastCallCount == 1)
        #expect(client.fetchCallCount == 1)
    }
    
    @Test func testBroadcastSkipsWhenTransactionKnownRemotely() async throws {
        let client = MockGatewayClient()
        let configuration = Network.Gateway.Configuration(initialStatus: .online,
                                                          initialHeaderUpdate: Date())
        let gateway = Network.Gateway(client: client, configuration: configuration)
        let transaction = Self.sampleTransaction(seed: 0x02)
        let expectedHash = Transaction.Hash(naturalOrder: HASH256.hash(transaction.encode()))
        
        client.fetchHandler = { hash in
            #expect(hash == expectedHash)
            return transaction
        }
        
        let result = try await gateway.broadcast(transaction)
        
        #expect(result == expectedHash)
        #expect(client.broadcastCallCount == 0)
        #expect(client.fetchCallCount == 1)
    }
    
    @Test func testBroadcastRespectsPoolHealth() async throws {
        let client = MockGatewayClient()
        let configuration = Network.Gateway.Configuration(initialStatus: .offline,
                                                          initialHeaderUpdate: Date())
        let gateway = Network.Gateway(client: client, configuration: configuration)
        let transaction = Self.sampleTransaction(seed: 0x03)
        
        await #expect(throws: Network.Gateway.Error(reason: .poolUnhealthy(.offline),
                                                    retry: .after(configuration.healthRetryDelay))) {
            _ = try await gateway.broadcast(transaction)
        }
        
        #expect(client.broadcastCallCount == 0)
    }
    
    @Test func testBroadcastRespectsHeaderFreshness() async throws {
        let client = MockGatewayClient()
        let configuration = Network.Gateway.Configuration(headerFreshness: 1,
                                                          healthRetryDelay: 2,
                                                          initialStatus: .online,
                                                          initialHeaderUpdate: Date().addingTimeInterval(-10))
        let gateway = Network.Gateway(client: client, configuration: configuration)
        let transaction = Self.sampleTransaction(seed: 0x04)
        
        await #expect(throws: Network.Gateway.Error(reason: .headersStale(since: configuration.initialHeaderUpdate),
                                                    retry: .after(configuration.healthRetryDelay))) {
            _ = try await gateway.broadcast(transaction)
        }
        
        #expect(client.broadcastCallCount == 0)
    }
    
    @Test func testBroadcastInterpretsAdapterDuplicate() async throws {
        let client = MockGatewayClient()
        let configuration = Network.Gateway.Configuration(initialStatus: .online,
                                                          initialHeaderUpdate: Date())
        let gateway = Network.Gateway(client: client, configuration: configuration)
        let transaction = Self.sampleTransaction(seed: 0x05)
        let duplicateHash = Transaction.Hash(naturalOrder: Data(repeating: 0x55, count: 32))
        
        client.broadcastHandler = { _ in throw MockError.duplicate }
        client.fetchHandler = { _ in nil }
        client.broadcastErrorInterpreter = { error, expected in
            #expect(error as? MockError == .duplicate)
            return .alreadyKnown(duplicateHash)
        }
        
        let result = try await gateway.broadcast(transaction)
        
        #expect(result == duplicateHash)
        #expect(client.broadcastCallCount == 1)
    }
    
    @Test func testGatewayNormalizesTransportErrors() async throws {
        let client = MockGatewayClient()
        let configuration = Network.Gateway.Configuration(initialStatus: .online,
                                                          initialHeaderUpdate: Date())
        let gateway = Network.Gateway(client: client, configuration: configuration)
        let hash = Transaction.Hash(naturalOrder: Data(repeating: 0x99, count: 32))
        
        client.rawHandler = { _ in throw MockError.transport }
        
        await #expect(throws: Network.Gateway.Error(reason: .transport(description: MockError.transportDescription),
                                                    retry: .after(configuration.healthRetryDelay))) {
            _ = try await gateway.getRawTransaction(for: hash)
        }
    }
}

extension NetworkGatewayTests {
    private static func sampleTransaction(seed: UInt8) -> Transaction {
        let previous = Transaction.Hash(naturalOrder: Data(repeating: seed, count: 32))
        let input = Transaction.Input(previousTransactionHash: previous,
                                      previousTransactionOutputIndex: 0,
                                      unlockingScript: Data(),
                                      sequence: 0)
        let output = Transaction.Output(value: 1_000,
                                        lockingScript: Data([0x51]))
        return Transaction(version: 2,
                           inputs: [input],
                           outputs: [output],
                           lockTime: 0)
    }
}

// MARK: - Test doubles

final class MockGatewayClient: Network.Gateway.Client, @unchecked Sendable {
    var currentMempool: Set<Transaction.Hash> = []
    
    var broadcastCallCount = 0
    var fetchCallCount = 0
    
    var broadcastHandler: (@Sendable (Transaction) async throws -> Transaction.Hash)?
    var fetchHandler: (@Sendable (Transaction.Hash) async throws -> Transaction?)?
    var rawHandler: (@Sendable (Transaction.Hash) async throws -> Data)?
    var detailedHandler: (@Sendable (Transaction.Hash) async throws -> Transaction.Detailed)?
    var estimateFeeHandler: (@Sendable (Int) async throws -> Satoshi)?
    var relayFeeHandler: (@Sendable () async throws -> Satoshi)?
    var headerHandler: (@Sendable (UInt32) async throws -> Network.Gateway.HeaderPayload?)?
    var pingHandler: (@Sendable () async throws -> Void)?
    var broadcastErrorInterpreter: ((Swift.Error, Transaction.Hash) -> Network.Gateway.BroadcastResolution?)?
    
    func broadcast(_ transaction: Transaction) async throws -> Transaction.Hash {
        broadcastCallCount += 1
        if let broadcastHandler {
            return try await broadcastHandler(transaction)
        }
        throw MockError.unhandled
    }
    
    func fetch(_ hash: Transaction.Hash) async throws -> Transaction? {
        fetchCallCount += 1
        if let fetchHandler {
            return try await fetchHandler(hash)
        }
        return nil
    }
    
    func getRawTransaction(for hash: Transaction.Hash) async throws -> Data {
        if let rawHandler {
            return try await rawHandler(hash)
        }
        throw MockError.unhandled
    }
    
    func getDetailedTransaction(for hash: Transaction.Hash) async throws -> Transaction.Detailed {
        if let detailedHandler {
            return try await detailedHandler(hash)
        }
        throw MockError.unhandled
    }
    
    func getEstimateFee(targetBlocks: Int) async throws -> Satoshi {
        if let estimateFeeHandler {
            return try await estimateFeeHandler(targetBlocks)
        }
        throw MockError.unhandled
    }
    
    func getRelayFee() async throws -> Satoshi {
        if let relayFeeHandler {
            return try await relayFeeHandler()
        }
        throw MockError.unhandled
    }
    
    func getHeader(height: UInt32) async throws -> Network.Gateway.HeaderPayload? {
        if let headerHandler {
            return try await headerHandler(height)
        }
        return nil
    }
    
    func pingHeadersTip() async throws {
        if let pingHandler {
            try await pingHandler()
            return
        }
    }
    
    func interpretBroadcastError(_ error: Swift.Error,
                                 expectedHash: Transaction.Hash) -> Network.Gateway.BroadcastResolution? {
        broadcastErrorInterpreter?(error, expectedHash)
    }
}

enum MockError: Swift.Error, Equatable {
    case duplicate
    case transport
    case unhandled
}

extension MockError: CustomStringConvertible {
    var description: String {
        switch self {
        case .duplicate:
            return "Duplicate transaction"
        case .transport:
            return Self.transportDescription
        case .unhandled:
            return "Unhandled mock call"
        }
    }
    
    static var transportDescription: String { "Mock transport failure" }
}
