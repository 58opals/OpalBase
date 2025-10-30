import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession Requests", .tags(.network, .integration))
struct NetworkFulcrumSessionRequestTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
    @Test("fetchHeaderTip reports the latest block header", .timeLimit(.minutes(1)))
    func testFetchHeaderTipReturnsRecentHeight() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        #expect(await session.state == .running)
        
        let tip = try await session.fetchHeaderTip()
        
        #expect(tip.height > 0)
        #expect(tip.hex.count == 160)
    }
    
    @Test("requests before start throw sessionNotStarted", .timeLimit(.minutes(1)))
    func testFetchBeforeStartThrowsSessionNotStarted() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        await #expect(throws: Network.FulcrumSession.Error.sessionNotStarted) {
            _ = try await session.fetchHeaderTip()
        }
    }
    
    @Test("address balance matches script hash balance", .timeLimit(.minutes(1)))
    func testFetchAddressAndScriptHashBalanceMatch() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let addressBalance = try await session.fetchAddressBalance(Self.sampleAddress)
        
        let address = try Address(Self.sampleAddress)
        let scriptData = address.lockingScript.data
        let scriptHash = SHA256.hash(scriptData).reversedData.hexadecimalString
        
        let scriptHashBalance = try await session.fetchScriptHashBalance(scriptHash)
        
        #expect(addressBalance.confirmed == scriptHashBalance.confirmed)
        #expect(addressBalance.unconfirmed == scriptHashBalance.unconfirmed)
        #expect(addressBalance.confirmed >= 0)
    }
    
    @Test("merkle proof aligns with address history", .timeLimit(.minutes(1)))
    func testFetchTransactionMerkleProofMatchesHistory() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let historyResponse = try await session.submit(
            method: .blockchain(.address(.getHistory(address: Self.sampleAddress, fromHeight: nil, toHeight: nil, includeUnconfirmed: true))),
            responseType: SwiftFulcrum.Response.Result.Blockchain.Address.GetHistory.self
        )
        
        guard case .single(_, let history) = historyResponse else {
            #expect(Bool(false), "Expected history as a single response")
            return
        }
        
        guard let confirmedTransaction = history.transactions.first(where: { $0.height > 0 }) else {
            #expect(Bool(false), "Sample address does not have a confirmed transaction to validate merkle proof")
            return
        }
        
        let merkleProof = try await session.fetchTransactionMerkleProof(forTransactionHash: confirmedTransaction.transactionHash)
        
        #expect(!merkleProof.merkle.isEmpty)
        #expect(merkleProof.blockHeight == UInt(confirmedTransaction.height))
    }
    
    @Test("merkle proof reports RPC error for unknown transaction", .timeLimit(.minutes(1)))
    func testFetchTransactionMerkleProofForUnknownTransaction() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        let missingTransactionHash = String(repeating: "0", count: 64)
        
        do {
            _ = try await session.fetchTransactionMerkleProof(forTransactionHash: missingTransactionHash)
            #expect(Bool(false), "Expected RPC error for unknown transaction hash")
        } catch let error as SwiftFulcrum.Fulcrum.Error {
            switch error {
            case .rpc(let serverError):
                #expect(!serverError.message.isEmpty)
            default:
                #expect(Bool(false), "Expected RPC error, received \(String(reflecting: error))")
            }
        } catch {
            #expect(Bool(false), "Expected Fulcrum error, received \(error)")
        }
    }
    
    @Test("broadcast rejects malformed transaction payload", .timeLimit(.minutes(1)))
    func testBroadcastTransactionRejectsMalformedPayload() async throws {
        let session = try await Network.FulcrumSession(serverAddress: Self.healthyServerAddress)
        defer { Task { try? await session.stop() } }
        
        try await session.start()
        
        do {
            _ = try await session.broadcastTransaction("00")
            #expect(Bool(false), "Expected RPC error when broadcasting malformed transaction")
        } catch let error as SwiftFulcrum.Fulcrum.Error {
            switch error {
            case .rpc(let serverError):
                #expect(!serverError.message.isEmpty)
            default:
                #expect(Bool(false), "Expected RPC error, received \(String(reflecting: error))")
            }
        } catch {
            #expect(Bool(false), "Expected Fulcrum error, received \(error)")
        }
    }
}
