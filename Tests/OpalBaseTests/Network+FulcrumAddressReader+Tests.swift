import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumAddressReader", .tags(.network))
struct NetworkFulcrumAddressReaderTests {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let faultyServerAddress = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    private static let invalidServerAddress = URL(string: "not a url")!
    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let invalidCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
    
    @Test("fetches balance consistent with RPC response", .timeLimit(.minutes(1)))
    func testFetchBalanceReflectsServerState() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumAddressReader(client: client)
            let balance = try await reader.fetchBalance(for: Self.sampleCashAddress)
            #expect(balance.confirmed >= 0)
            
            let rpcBalance: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance = try await client.request(
                method: .blockchain(.address(.getBalance(address: Self.sampleCashAddress, tokenFilter: nil))),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance.self
            )
            #expect(rpcBalance.confirmed == balance.confirmed)
            #expect(rpcBalance.unconfirmed == balance.unconfirmed)
        }
    }
    
    @Test("fetches balances and history from a live fulcrum server", .timeLimit(.minutes(1)))
    func testFetchBalanceAndHistoryFromLiveServer() async throws {
        let configuration = Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectionTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 4,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumAddressReader(client: client)
            let balance = try await reader.fetchBalance(for: Self.sampleCashAddress)
            #expect(balance.confirmed >= 0)
            #expect(balance.unconfirmed >= 0)
            
            let historyWithUnconfirmed = try await reader.fetchHistory(
                for: Self.sampleCashAddress,
                includeUnconfirmed: true
            )
            #expect(!historyWithUnconfirmed.isEmpty)
            
            let confirmedHistory = try await reader.fetchHistory(
                for: Self.sampleCashAddress,
                includeUnconfirmed: false
            )
            #expect(historyWithUnconfirmed.count >= confirmedHistory.count)
            
            if let confirmedHeight = confirmedHistory.first?.blockHeight {
                #expect(historyWithUnconfirmed.contains { $0.blockHeight == confirmedHeight })
            }
        }
    }
    
    @Test("lists spendable outputs with expected locking script", .timeLimit(.minutes(1)))
    func testFetchUnspentOutputsProducesSpendableEntries() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumAddressReader(client: client)
            let expectedLockingScript = try Address(Self.sampleCashAddress).lockingScript.data
            
            let unspentOutputs = try await reader.fetchUnspentOutputs(for: Self.sampleCashAddress)
            #expect(!unspentOutputs.isEmpty)
            
            for output in unspentOutputs {
                #expect(output.value > 0)
                #expect(output.lockingScript == expectedLockingScript)
                #expect(output.previousTransactionHash.naturalOrder.count == 32)
            }
        }
    }
    
    @Test("retrieves history and respects unconfirmed flag", .timeLimit(.minutes(1)))
    func testFetchHistoryDifferentiatesUnconfirmedEntries() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumAddressReader(client: client)
            let confirmedHistory = try await reader.fetchHistory(for: Self.sampleCashAddress, includeUnconfirmed: false)
            let inclusiveHistory = try await reader.fetchHistory(for: Self.sampleCashAddress, includeUnconfirmed: true)
            
            #expect(!inclusiveHistory.isEmpty)
            #expect(Set(confirmedHistory.map(\.transactionIdentifier)).isSubset(of: Set(inclusiveHistory.map(\.transactionIdentifier))))
            #expect(confirmedHistory.allSatisfy { $0.blockHeight > 0 })
            
            if inclusiveHistory.count > confirmedHistory.count {
                #expect(inclusiveHistory.contains { $0.blockHeight <= 0 })
            }
        }
    }
    
    @Test("converts unspent outputs from the live server into wallet friendly structures", .timeLimit(.minutes(1)))
    func testFetchUnspentOutputsMatchesServerData() async throws {
        let configuration = Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectionTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 4,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumAddressReader(client: client)
            let rawUnspent: SwiftFulcrum.Response.Result.Blockchain.Address.ListUnspent = try await client.request(
                method: .blockchain(
                    .address(
                        .listUnspent(address: Self.sampleCashAddress, tokenFilter: nil)
                    )
                ),
                responseType: SwiftFulcrum.Response.Result.Blockchain.Address.ListUnspent.self
            )
            
            let walletUnspent = try await reader.fetchUnspentOutputs(for: Self.sampleCashAddress)
            #expect(walletUnspent.count == rawUnspent.items.count)
            
            let expectedLockingScript = try Address(Self.sampleCashAddress).lockingScript.data
            let itemsByIdentifier = rawUnspent.items.reduce(into: [String: SwiftFulcrum.Response.Result.Blockchain.Address.ListUnspent.Item]()) { result, item in
                let key = "\(item.transactionHash):\(item.transactionPosition)"
                result[key] = item
            }
            
            for output in walletUnspent {
                #expect(output.lockingScript == expectedLockingScript)
                let identifier = "\(output.previousTransactionHash.reverseOrder.hexadecimalString):\(output.previousTransactionOutputIndex)"
                let matchingItem = itemsByIdentifier[identifier]
                #expect(matchingItem != nil)
                if let matchingItem {
                    #expect(matchingItem.value == output.value)
                }
            }
        }
    }
    
    @Test("rejects invalid addresses before network usage", .timeLimit(.minutes(1)))
    func testFetchUnspentOutputsRejectsInvalidAddress1() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumAddressReader(client: client)
            var thrownError: Error?
            do {
                _ = try await reader.fetchUnspentOutputs(for: "not-an-address")
            } catch {
                thrownError = error
            }
            
            let failure = try #require(thrownError as? Network.Failure)
            #expect(failure.reason == .protocolViolation)
            if let message = failure.message {
                #expect(message.contains("Invalid address"))
            }
        }
    }
    
    @Test("rejects invalid addresses before reaching the network", .timeLimit(.minutes(1)))
    func testFetchUnspentOutputsRejectsInvalidAddress2() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumAddressReader(client: client)
            do {
                _ = try await reader.fetchUnspentOutputs(for: "invalid-address")
                #expect(Bool(false), "Expected an invalid address to throw a protocol violation failure")
            } catch let failure as Network.Failure {
                #expect(failure.reason == .protocolViolation)
                #expect(failure.message?.contains("Invalid address") ?? false)
            }
        }
    }
    
    @Test("translates invalid address errors for wallet validation", .timeLimit(.minutes(1)))
    func testFetchUnspentOutputsFailsForInvalidAddress() async throws {
        let configuration = Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectionTimeout: .seconds(12),
            maximumMessageSize: 8 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 2,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(5),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )
        
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            var capturedError: (any Error)?
            do {
                let reader = Network.FulcrumAddressReader(client: client)
                _ = try await reader.fetchUnspentOutputs(for: Self.invalidCashAddress)
                Issue.record("Expected fetch to throw for invalid address")
            } catch let failure as Network.Failure {
                #expect(failure.reason == .protocolViolation)
                if let message = failure.message {
                    #expect(message.contains("Invalid address"))
                }
            } catch {
                capturedError = error
            }
            
            if let capturedError {
                throw capturedError
            }
        }
    }
    
    @Test("subscribes to address updates and cancels cleanly", .timeLimit(.minutes(1)))
    func testSubscribeToAddressDeliversInitialSnapshot() async throws {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestSupport.withClient(configuration: configuration) { client in
            let reader = Network.FulcrumAddressReader(client: client)
            let stream = try await reader.subscribeToAddress(Self.sampleCashAddress)
            var iterator = stream.makeAsyncIterator()
            
            let initialUpdate = try await iterator.next()
            #expect(initialUpdate?.kind == .initialSnapshot)
            #expect(initialUpdate?.address == Self.sampleCashAddress)
            #expect(!(initialUpdate?.status?.isEmpty ?? true))
            
            let pendingChange = Task { try await iterator.next() }
            try await Task.sleep(nanoseconds: 200_000_000)
            pendingChange.cancel()
            
            do {
                _ = try await pendingChange.value
            } catch is CancellationError {
                // Expected when cancelling before a new update arrives.
            }
        }
    }
}
