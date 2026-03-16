// NetworkFulcrumAddressReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.AddressReader", .tags(.integration, .network))
struct NetworkFulcrumAddressReaderValidator {
    static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    static let backupServerAddress = URL(string: "wss://bch.loping.net:50004")!
    static let faultyServerAddress = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    static let invalidServerAddress = URL(string: "not a url")!
    static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    static let tokenCashAddress = "bitcoincash:qqe68ymghsw9derq3v2rgu2jc8a23ddv25t83hevfk"
    static let invalidCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"

    @Test("fetches balance consistent with RPC response", .timeLimit(.minutes(1)))
    func fetchBalanceReflectsServerState() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            let balance = try await reader.fetchBalance(for: Self.sampleCashAddress, tokenFilter: .include)
            #expect(balance.confirmed >= 0)

            let rpcBalance: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.GetBalance = try await client.request(
                method: .blockchain(.address(.getBalance(address: Self.sampleCashAddress, tokenFilter: .include))),
                responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.GetBalance.self
            )
            #expect(rpcBalance.confirmed == balance.confirmed)
            #expect(rpcBalance.unconfirmed == balance.unconfirmed)
        }
    }

    @Test("fetches balances and history from a live fulcrum server", .timeLimit(.minutes(1)))
    func fetchBalanceAndHistoryFromLiveServer() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 4,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            let balance = try await reader.fetchBalance(for: Self.sampleCashAddress, tokenFilter: .include)
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
    func fetchUnspentOutputsProducesSpendableEntries() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            let expectedLockingScript = try OpalBase.Address(Self.sampleCashAddress).lockingScript.data

            let unspentOutputs = try await reader.fetchUnspentOutputs(for: Self.sampleCashAddress, tokenFilter: .include)
            #expect(!unspentOutputs.isEmpty)

            for output in unspentOutputs {
                #expect(output.value > 0)
                #expect(output.lockingScript == expectedLockingScript)
                #expect(output.previousTransactionHash.naturalOrder.count == 32)
            }
        }
    }

    @Test("retrieves history and respects unconfirmed flag", .timeLimit(.minutes(1)))
    func fetchHistoryDifferentiatesUnconfirmedEntries() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
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
    func fetchUnspentOutputsMatchesServerData() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 4,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(10),
                jitterMultiplierRange: 0.9 ... 1.2
            )
        )

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.Fulcrum.AddressReader(client: client)
            let rawUnspent: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.ListUnspent = try await client.request(
                method: .blockchain(
                    .address(
                        .listUnspent(address: Self.sampleCashAddress, tokenFilter: .include)
                    )
                ),
                responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.ListUnspent.self
            )

            let walletUnspent = try await reader.fetchUnspentOutputs(for: Self.sampleCashAddress, tokenFilter: .include)
            #expect(walletUnspent.count == rawUnspent.items.count)

            let expectedLockingScript = try OpalBase.Address(Self.sampleCashAddress).lockingScript.data
            let itemsByIdentifier = rawUnspent.items.reduce(into: [String: SwiftFulcrum.RPC.Response.Result.Blockchain.Address.ListUnspent.Item]()) { result, item in
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
}
