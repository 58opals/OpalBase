// AddressBookUnspentTransactionOutputRefreshNetworkValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("AddressModel BookActor UTXOModel Refresh (NetworkModel)", .tags(.network, .cashTokens))
struct AddressBookUnspentTransactionOutputRefreshNetworkValidator {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let tokenCashAddress = "bitcoincash:qqe68ymghsw9derq3v2rgu2jc8a23ddv25t83hevfk"

    @Test("listunspent token data reaches the UTXOModel store", .timeLimit(.minutes(1)))
    func ingestNetworkTokenUnspentTransactionOutputs() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let address = try AddressModel(Self.tokenCashAddress)

        let configuration = NetworkModel.Configuration(serverURLs: [Self.primaryServerAddress, Self.backupServerAddress])
        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = NetworkModel.FulcrumAddressReaderModel(client: client)

            let tokenOutputs = try await reader.fetchUnspentOutputs(
                for: Self.tokenCashAddress,
                tokenFilter: .only
            )

            #expect(!tokenOutputs.isEmpty)
            #expect(tokenOutputs.allSatisfy { $0.tokenData != nil })

            _ = try await book.replaceUTXOs(
                for: address,
                with: tokenOutputs,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )

            let storedOutputs = await book.listUTXOs(for: address)
            #expect(storedOutputs.count == tokenOutputs.count)
            #expect(storedOutputs.allSatisfy { $0.tokenData != nil })
        }
    }
}

