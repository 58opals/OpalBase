// TransactionHistoryTokenDeltaValidator+TestError.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("TransactionModel history token deltas", .tags(.unit, .cashTokens))
struct TransactionHistoryTokenDeltaValidator {
    @Test("computes token deltas for a synthetic transfer")
    func tokenDeltaForSyntheticTransfer() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let externalAddress = try makeExternalAddress()
        
        let category = try CashTokensModel.CategoryIDModel(transactionOrderData: Data(repeating: 0x11, count: 32))
        let removedToken = try CashTokensModel.NFTModel(capability: .mutable, commitment: Data([0x0a]))
        let addedToken = try CashTokensModel.NFTModel(capability: .minting, commitment: Data([0x0b]))
        let inputTokenData = CashTokensModel.TokenData(category: category, amount: 100, nft: removedToken)
        let changeTokenData = CashTokensModel.TokenData(category: category, amount: 30, nft: nil)
        let externalTokenData = CashTokensModel.TokenData(category: category, amount: 70, nft: removedToken)
        let additionTokenData = CashTokensModel.TokenData(category: category, amount: nil, nft: addedToken)
        
        let previousHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x01, count: 32))
        let previousInput = TransactionModel.InputModel(previousTransactionHash: TransactionModel.HashModel(naturalOrder: Data(repeating: 0x00, count: 32)),
                                              previousTransactionOutputIndex: 0,
                                              unlockingScript: Data())
        let previousOutput = TransactionModel.OutputModel(value: 1_000,
                                                lockingScript: walletAddress.lockingScript.data,
                                                tokenData: inputTokenData)
        let previousTransaction = TransactionModel(version: 2,
                                              inputs: [previousInput],
                                              outputs: [previousOutput],
                                              lockTime: 0)
        let previousRawTransaction = try previousTransaction.encode()
        
        let currentHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x02, count: 32))
        let currentInput = TransactionModel.InputModel(previousTransactionHash: previousHash,
                                             previousTransactionOutputIndex: 0,
                                             unlockingScript: Data())
        let changeOutput = TransactionModel.OutputModel(value: 600,
                                              lockingScript: walletAddress.lockingScript.data,
                                              tokenData: changeTokenData)
        let externalOutput = TransactionModel.OutputModel(value: 500,
                                                lockingScript: externalAddress.lockingScript.data,
                                                tokenData: externalTokenData)
        let additionOutput = TransactionModel.OutputModel(value: 550,
                                                lockingScript: walletAddress.lockingScript.data,
                                                tokenData: additionTokenData)
        let currentTransaction = TransactionModel(version: 2,
                                             inputs: [currentInput],
                                             outputs: [changeOutput, externalOutput, additionOutput],
                                             lockTime: 0)
        let currentRawTransaction = try currentTransaction.encode()
        
        let addressReader = AddressReaderClient(historyByAddress: [
            walletAddress.string: [
                NetworkModel.TransactionHistoryEntryModel(transactionIdentifier: currentHash.reverseOrder.hexadecimalString,
                                                blockHeight: 1,
                                                fee: nil)
            ]
        ])
        let transactionReader = TransactionReaderClient(rawTransactionsByHash: [
            previousHash: previousRawTransaction,
            currentHash: currentRawTransaction
        ])
        
        let changeSet = try await book.refreshTransactionHistory(using: addressReader,
                                                                 includeUnconfirmed: true,
                                                                 transactionReader: transactionReader)
        let record = try #require(changeSet.inserted.first)
        #expect(record.tokenDelta.fungibleDeltasByCategory[category] == -70)
        #expect(record.tokenDelta.nonFungibleTokenAdditions.contains(additionTokenData))
        let removalTokenData = CashTokensModel.TokenData(category: category, amount: nil, nft: removedToken)
        #expect(record.tokenDelta.nonFungibleTokenRemovals.contains(removalTokenData))
        #expect(record.tokenDelta.bitcoinCashLockedInTokenOutputDelta == 150)
    }
}

private extension TransactionHistoryTokenDeltaValidator {
    enum TestError: Swift.Error {
        case unexpectedRequest
        case missingTransaction
    }
    
    struct AddressReaderClient: NetworkModel.AddressReadable {
        let historyByAddress: [String: [NetworkModel.TransactionHistoryEntryModel]]
        
        func fetchBalance(for address: String, tokenFilter: NetworkModel.TokenFilter) async throws -> NetworkModel.AddressBalanceModel {
            throw TestError.unexpectedRequest
        }
        
        func fetchUnspentOutputs(for address: String, tokenFilter: NetworkModel.TokenFilter) async throws -> [TransactionModel.OutputModel.UnspentModel] {
            .init()
        }
        
        func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [NetworkModel.TransactionHistoryEntryModel] {
            historyByAddress[address, default: .init()]
        }
        
        func fetchFirstUse(for address: String) async throws -> NetworkModel.AddressFirstUseModel? {
            nil
        }
        
        func fetchMempoolTransactions(for address: String) async throws -> [NetworkModel.TransactionHistoryEntryModel] {
            .init()
        }
        
        func fetchScriptHash(for address: String) async throws -> String {
            ""
        }
        
        func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<NetworkModel.AddressSubscriptionUpdateModel, any Swift.Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }
    
    struct TransactionReaderClient: NetworkModel.TransactionReadableClient {
        let rawTransactionsByHash: [TransactionModel.HashModel: Data]
        
        func fetchRawTransaction(for transactionHash: TransactionModel.HashModel) async throws -> Data {
            guard let data = rawTransactionsByHash[transactionHash] else {
                throw TestError.missingTransaction
            }
            return data
        }
    }
    
    func makeAddressBook() async throws -> AddressModel.BookActor {
        let mnemonic = try MnemonicModel(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = PrivateKeyModel.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        return try await AddressModel.BookActor(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                      purpose: .bip44,
                                      coinType: .bitcoinCash,
                                      account: .init(rawIndexInteger: 0),
                                      gapLimit: 2)
    }
    
    func makeExternalAddress() throws -> AddressModel {
        let privateKey = try PrivateKeyModel(data: Data(repeating: 0x03, count: 32))
        let publicKey = try PublicKeyModel(privateKey: privateKey)
        return try AddressModel(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
    }
}

