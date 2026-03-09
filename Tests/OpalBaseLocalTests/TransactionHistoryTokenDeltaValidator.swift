// TransactionHistoryTokenDeltaValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Transaction history token deltas", .tags(.unit, .cashTokens))
struct TransactionHistoryTokenDeltaValidator {
    @Test("computes token deltas for a synthetic transfer")
    func tokenDeltaForSyntheticTransfer() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let externalAddress = try makeExternalAddress()
        
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x11, count: 32))
        let removedToken = try OpalBase.CashTokens.NFT(capability: .mutable, commitment: Data([0x0a]))
        let addedToken = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data([0x0b]))
        let inputTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 100, nft: removedToken)
        let changeTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 30, nft: nil)
        let externalTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 70, nft: removedToken)
        let additionTokenData = OpalBase.CashTokens.TokenData(category: category, amount: nil, nft: addedToken)
        
        let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32))
        let previousInput = OpalBase.Transaction.Input(previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
                                              previousTransactionOutputIndex: 0,
                                              unlockingScript: Data())
        let previousOutput = OpalBase.Transaction.Output(value: 1_000,
                                                lockingScript: walletAddress.lockingScript.data,
                                                tokenData: inputTokenData)
        let previousTransaction = OpalBase.Transaction(version: 2,
                                              inputs: [previousInput],
                                              outputs: [previousOutput],
                                              lockTime: 0)
        let previousRawTransaction = try previousTransaction.encode()
        
        let currentHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x02, count: 32))
        let currentInput = OpalBase.Transaction.Input(previousTransactionHash: previousHash,
                                             previousTransactionOutputIndex: 0,
                                             unlockingScript: Data())
        let changeOutput = OpalBase.Transaction.Output(value: 600,
                                              lockingScript: walletAddress.lockingScript.data,
                                              tokenData: changeTokenData)
        let externalOutput = OpalBase.Transaction.Output(value: 500,
                                                lockingScript: externalAddress.lockingScript.data,
                                                tokenData: externalTokenData)
        let additionOutput = OpalBase.Transaction.Output(value: 550,
                                                lockingScript: walletAddress.lockingScript.data,
                                                tokenData: additionTokenData)
        let currentTransaction = OpalBase.Transaction(version: 2,
                                             inputs: [currentInput],
                                             outputs: [changeOutput, externalOutput, additionOutput],
                                             lockTime: 0)
        let currentRawTransaction = try currentTransaction.encode()
        
        let addressReader = AddressReaderClient(historyByAddress: [
            walletAddress.string: [
                OpalBase.Network.TransactionHistoryEntry(transactionIdentifier: currentHash.reverseOrder.hexadecimalString,
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
        let removalTokenData = OpalBase.CashTokens.TokenData(category: category, amount: nil, nft: removedToken)
        #expect(record.tokenDelta.nonFungibleTokenRemovals.contains(removalTokenData))
        #expect(record.tokenDelta.bitcoinCashLockedInTokenOutputDelta == 150)
    }
}

private extension TransactionHistoryTokenDeltaValidator {
    enum TestError: Swift.Error {
        case unexpectedRequest
        case missingTransaction
    }
    
    struct AddressReaderClient: OpalBase.Network.AddressReadable {
        let historyByAddress: [String: [OpalBase.Network.TransactionHistoryEntry]]
        
        func fetchBalance(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance {
            throw TestError.unexpectedRequest
        }
        
        func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent] {
            .init()
        }
        
        func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            historyByAddress[address, default: .init()]
        }
        
        func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? {
            nil
        }
        
        func fetchMempoolTransactions(for address: String) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            .init()
        }
        
        func fetchScriptHash(for address: String) async throws -> String {
            ""
        }
        
        func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }
    
    struct TransactionReaderClient: OpalBase.Network.TransactionReadableClient {
        let rawTransactionsByHash: [OpalBase.Transaction.Hash: Data]
        
        func fetchRawTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> Data {
            guard let data = rawTransactionsByHash[transactionHash] else {
                throw TestError.missingTransaction
            }
            return data
        }
    }
    
    func makeAddressBook() async throws -> OpalBase.Address.Book {
        let mnemonic = try OpalBase.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = OpalBase.PrivateKey.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        return try await OpalBase.Address.Book(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                      purpose: .bip44,
                                      coinType: .bitcoinCash,
                                      account: .init(rawIndexInteger: 0),
                                      gapLimit: 2)
    }
    
    func makeExternalAddress() throws -> OpalBase.Address {
        let privateKey = try OpalBase.PrivateKey(data: Data(repeating: 0x03, count: 32))
        let publicKey = try OpalBase.PublicKey(privateKey: privateKey)
        return try OpalBase.Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
    }
}
