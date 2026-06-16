// TokenMetadataSyncFixture.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalBase

enum TokenMetadataSyncFixture {
    static func makeAuthbase(byte: UInt8) throws -> TokenMetadataSyncAuthbaseFixture {
        let identityAddress = try OpalBase.Address(string: AccountTestFixtures.standardAddressString)
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: byte, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let transaction = OpalBase.Transaction(
            version: 1,
            inputs: [input],
            outputs: [
                OpalBase.Transaction.Output(
                    value: 1,
                    lockingScript: identityAddress.lockingScript.data
                )
            ],
            lockTime: 0
        )
        let rawTransaction = try transaction.encode()
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawTransaction)
        )
        return try TokenMetadataSyncAuthbaseFixture(
            rawTransaction: rawTransaction,
            transactionHash: transactionHash,
            category: OpalBase.CashTokens.CategoryID(transactionOrderData: transactionHash.naturalOrder)
        )
    }

    static func makeCategory(byte: UInt8) throws -> OpalBase.CashTokens.CategoryID {
        try OpalBase.CashTokens.CategoryID(
            hexFromRPC: Data(repeating: byte, count: 32).hexadecimalString
        )
    }

    static func makeAuthchain(
        authbases: [TokenMetadataSyncAuthbaseFixture],
        publicationScript: Data
    ) throws -> TokenMetadataSyncAuthchainFixture {
        let rawPublicationTransaction = try makePublicationTransaction(
            authbaseHashes: authbases.map(\.transactionHash),
            publicationScript: publicationScript
        )
        let publicationHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawPublicationTransaction)
        )
        var mutableRawTransactionsByHash = Dictionary(
            uniqueKeysWithValues: authbases.map { authbase in
                (authbase.transactionHash, authbase.rawTransaction)
            }
        )
        mutableRawTransactionsByHash[publicationHash] = rawPublicationTransaction
        let rawTransactionsByHash = mutableRawTransactionsByHash

        let transactionReader = OpalBase.Network.TransactionReader { transactionHash in
            guard let rawTransaction = rawTransactionsByHash[transactionHash] else {
                throw TokenMetadataSyncStubError.notImplemented
            }
            return rawTransaction
        }

        return TokenMetadataSyncAuthchainFixture(
            transactionReader: transactionReader,
            addressReader: makeAddressReader(publicationHash: publicationHash)
        )
    }

    static func makeAddressReader(
        publicationHash: OpalBase.Transaction.Hash
    ) -> OpalBase.Network.AddressReader {
        OpalBase.Network.AddressReader(
            fetchBalance: { _, _ in throw TokenMetadataSyncStubError.notImplemented },
            fetchUnspentOutputs: { _, _ in throw TokenMetadataSyncStubError.notImplemented },
            fetchHistory: { _, _ in
                [
                    OpalBase.Network.TransactionHistoryEntry(
                        transactionIdentifier: publicationHash.reverseOrder.hexadecimalString,
                        blockHeight: 1,
                        fee: nil
                    )
                ]
            },
            fetchFirstUse: { _ in nil },
            fetchMempoolTransactions: { _ in [] },
            fetchScriptHash: { _ in throw TokenMetadataSyncStubError.notImplemented },
            subscribeToAddress: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )
    }

    static func makePublicationScript(
        registryData: Data,
        registryURL: URL
    ) -> Data {
        let prefix = Data([0x42, 0x43, 0x4d, 0x52])
        var script = Data([0x6a])
        script.append(Data.push(prefix))
        script.append(Data.push(OpalCrypto.Hashing.sha256(registryData)))
        script.append(Data.push(Data(registryURL.absoluteString.utf8)))
        return script
    }

    static func withRegistryFetcher<T>(
        registryData: Data,
        operation: (OpalBase.CashTokens.BCMR.Client.Fetcher) async throws -> T
    ) async throws -> T {
        let session = makeRegistrySession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, registryData)
        }
        defer {
            TokenMetadataSyncRegistryURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let registryFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 64 * 1_024
        )
        return try await operation(registryFetcher)
    }

    private static func makePublicationTransaction(
        authbaseHashes: [OpalBase.Transaction.Hash],
        publicationScript: Data
    ) throws -> Data {
        let identityAddress = try OpalBase.Address(string: AccountTestFixtures.standardAddressString)
        let transaction = OpalBase.Transaction(
            version: 1,
            inputs: authbaseHashes.map { authbaseHash in
                OpalBase.Transaction.Input(
                    previousTransactionHash: authbaseHash,
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data()
                )
            },
            outputs: [
                OpalBase.Transaction.Output(
                    value: 1,
                    lockingScript: identityAddress.lockingScript.data
                ),
                OpalBase.Transaction.Output(
                    value: 0,
                    lockingScript: publicationScript
                )
            ],
            lockTime: 0
        )
        return try transaction.encode()
    }

    private static func makeRegistrySession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TokenMetadataSyncRegistryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        TokenMetadataSyncRegistryURLProtocol.requestHandler = { request in
            return try handler(request)
        }
        return session
    }
}
