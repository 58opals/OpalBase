import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.FulcrumSession Requests", .tags(.network, .integration))
struct NetworkFulcrumSessionRequestTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let sampleAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    
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
    
    private func withRunningSession(
        using serverAddress: URL = Self.healthyServerAddress,
        configuration: SwiftFulcrum.Fulcrum.Configuration = .init(),
        perform: @escaping @Sendable (Network.FulcrumSession) async throws -> Void
    ) async throws {
        try await withSession(using: serverAddress, configuration: configuration) { session in
            try await session.start()
            #expect(await session.isRunning)
            try await perform(session)
        }
    }
    
    private func makeScriptHash(for address: String) throws -> String {
        let address = try Address(address)
        let lockingScript = address.lockingScript.data
        let digest = SHA256.hash(lockingScript)
        return Data(digest.reversed()).map { String(format: "%02x", $0) }.joined()
    }
}

extension NetworkFulcrumSessionRequestTests {
    @Test("fetchHeaderTip surfaces the latest chain tip")
    func testFetchHeaderTipProvidesRecentChainInformation() async throws {
        try await withRunningSession { session in
            let tip = try await session.fetchHeaderTip()
            
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
        }
    }
    
    @Test("fetchAddressBalance aligns with script hash balance")
    func testFetchAddressAndScriptHashBalanceConsistency() async throws {
        try await withRunningSession { session in
            let addressBalance = try await session.fetchAddressBalance(Self.sampleAddress)
            let scriptHash = try makeScriptHash(for: Self.sampleAddress)
            let scriptHashBalance = try await session.fetchScriptHashBalance(scriptHash)
            
            #expect(addressBalance.confirmed == scriptHashBalance.confirmed)
            #expect(addressBalance.unconfirmed == scriptHashBalance.unconfirmed)
        }
    }
    
    @Test("fetchTransactionMerkleProof matches historical data")
    func testFetchTransactionMerkleProofMatchesHistory() async throws {
        try await withRunningSession { session in
            let scriptHash = try makeScriptHash(for: Self.sampleAddress)
            let historyResponse = try await session.submit(
                method: .blockchain(.scripthash(.getHistory(scripthash: scriptHash, fromHeight: nil, toHeight: nil, includeUnconfirmed: true))),
                responseType: SwiftFulcrum.Response.Result.Blockchain.ScriptHash.GetHistory.self
            )
            
            guard case .single(_, let history) = historyResponse else {
                return #expect(Bool(false), "Expected single history response for sample script hash")
            }
            print(history.transactions.count)
            
            guard let confirmed = history.transactions.first(where: { $0.height > 0 }) else {
                return #expect(Bool(false), "Expected at least one confirmed transaction in script hash history")
            }
            print(confirmed.transactionHash)
            
            let merkleProof = try await session.fetchTransactionMerkleProof(
                forTransactionHash: confirmed.transactionHash
            )
            print(merkleProof.blockHeight)
            
            #expect(merkleProof.blockHeight == UInt(confirmed.height))
            #expect(!merkleProof.merkle.isEmpty)
        }
    }
    
    @Test("broadcasting invalid transactions surfaces server errors")
    func testBroadcastTransactionSurfacesServerErrors() async throws {
        try await withRunningSession { session in
            await #expect(throws: SwiftFulcrum.Fulcrum.Error.self) {
                try await session.broadcastTransaction("00")
            }
        }
    }
}
