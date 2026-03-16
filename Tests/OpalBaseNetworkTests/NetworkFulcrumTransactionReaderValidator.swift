import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.TransactionReader", .tags(.integration, .network))
struct NetworkFulcrumTransactionReaderValidator {
    private static let fallbackServers: [URL] = [
        URL(string: "wss://bch.imaginary.cash:50004")!,
        URL(string: "wss://fulcrum.greyh.at:50004")!,
        URL(string: "wss://electrum.imaginary.cash:50004")!
    ]

    private static let confirmedTransactionIdentifier =
        "0a793cf3cc8de12f7a4c43912ecefc8a6676564828bf501bd2177bf83fca3873"

    @Test("matches live raw and verbose transaction responses", .timeLimit(.minutes(1)))
    func fetchesLiveRawAndDetailedTransactions() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let configuration = makeConfiguration()

        try await NetworkTestClient.withClient(configuration: configuration) { client in
            let reader = OpalBase.Network.FulcrumTransactionReader(client: client)
            let transactionHash = try OpalBase.Network.decodeTransactionHash(
                from: Self.confirmedTransactionIdentifier
            )

            let rawHexadecimal: String = try await client.request(
                method: .blockchain(
                    .transaction(
                        .get(
                            transactionHash: Self.confirmedTransactionIdentifier,
                            isVerbose: false
                        )
                    )
                ),
                responseType: String.self
            )
            let verbose: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.Get = try await client.request(
                method: .blockchain(
                    .transaction(
                        .get(
                            transactionHash: Self.confirmedTransactionIdentifier,
                            isVerbose: true
                        )
                    )
                ),
                responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.Get.self
            )

            let rawTransactionData = try await reader.fetchRawTransaction(for: transactionHash)
            let detailed = try await reader.fetchDetailedTransaction(for: transactionHash)
            let expectedRawTransactionData = try Data(hexadecimalString: rawHexadecimal)
            let expectedVerboseRawTransactionData = try Data(hexadecimalString: verbose.hex)

            #expect(rawHexadecimal == verbose.hex)
            #expect(rawTransactionData == expectedRawTransactionData)
            #expect(detailed.hash == transactionHash)
            #expect(detailed.rawTransactionData == rawTransactionData)
            #expect(detailed.rawTransactionData == expectedVerboseRawTransactionData)
            #expect(!detailed.transaction.inputs.isEmpty)
            #expect(!detailed.transaction.outputs.isEmpty)
            #expect((detailed.confirmations ?? 0) > 0)
        }
    }
}

private extension NetworkFulcrumTransactionReaderValidator {
    func makeConfiguration() -> OpalBase.Network.Configuration {
        let environmentServer = ProcessInfo.processInfo.environment["OPAL_FULCRUM_URL"].flatMap(URL.init(string:))
        return OpalBase.Network.Configuration(
            serverURLs: [environmentServer].compactMap { $0 } + Self.fallbackServers,
            connectTimeout: .seconds(12),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 2,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(8),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )
    }
}
