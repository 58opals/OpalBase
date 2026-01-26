import Foundation
import Testing
@testable import OpalBase

@Suite("Transaction history token deltas", .tags(.unit, .cashTokens))
struct TransactionHistoryTokenDeltaTests {
    @Test("computes token deltas for a synthetic transfer")
    func testTokenDeltaForSyntheticTransfer() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let externalAddress = try makeExternalAddress()
        
        let category = try CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x11, count: 32))
        let removedToken = try CashTokens.NFT(capability: .mutable, commitment: Data([0x0a]))
        let addedToken = try CashTokens.NFT(capability: .minting, commitment: Data([0x0b]))
        let inputTokenData = CashTokens.TokenData(category: category, amount: 100, nft: removedToken)
        let changeTokenData = CashTokens.TokenData(category: category, amount: 30, nft: nil)
        let externalTokenData = CashTokens.TokenData(category: category, amount: 70, nft: removedToken)
        let additionTokenData = CashTokens.TokenData(category: category, amount: nil, nft: addedToken)
        
        let previousHash = Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32))
        let previousInput = Transaction.Input(previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
                                              previousTransactionOutputIndex: 0,
                                              unlockingScript: Data())
        let previousOutput = Transaction.Output(value: 1_000,
                                                lockingScript: walletAddress.lockingScript.data,
                                                tokenData: inputTokenData)
        let previousTransaction = Transaction(version: 2,
                                              inputs: [previousInput],
                                              outputs: [previousOutput],
                                              lockTime: 0)
        let previousRawTransaction = try previousTransaction.encode()
        
        let currentHash = Transaction.Hash(naturalOrder: Data(repeating: 0x02, count: 32))
        let currentInput = Transaction.Input(previousTransactionHash: previousHash,
                                             previousTransactionOutputIndex: 0,
                                             unlockingScript: Data())
        let changeOutput = Transaction.Output(value: 600,
                                              lockingScript: walletAddress.lockingScript.data,
                                              tokenData: changeTokenData)
        let externalOutput = Transaction.Output(value: 500,
                                                lockingScript: externalAddress.lockingScript.data,
                                                tokenData: externalTokenData)
        let additionOutput = Transaction.Output(value: 550,
                                                lockingScript: walletAddress.lockingScript.data,
                                                tokenData: additionTokenData)
        let currentTransaction = Transaction(version: 2,
                                             inputs: [currentInput],
                                             outputs: [changeOutput, externalOutput, additionOutput],
                                             lockTime: 0)
        let currentRawTransaction = try currentTransaction.encode()
        
        let addressReader = AddressReaderStub(historyByAddress: [
            walletAddress.string: [
                Network.TransactionHistoryEntry(transactionIdentifier: currentHash.reverseOrder.hexadecimalString,
                                                blockHeight: 1,
                                                fee: nil)
            ]
        ])
        let transactionReader = TransactionReaderStub(rawTransactionsByHash: [
            previousHash: previousRawTransaction,
            currentHash: currentRawTransaction
        ])
        
        let changeSet = try await book.refreshTransactionHistory(using: addressReader,
                                                                 includeUnconfirmed: true,
                                                                 transactionReader: transactionReader)
        let record = try #require(changeSet.inserted.first)
        #expect(record.tokenDelta.fungibleDeltasByCategory[category] == -70)
        #expect(record.tokenDelta.nonFungibleTokenAdditions.contains(additionTokenData))
        let removalTokenData = CashTokens.TokenData(category: category, amount: nil, nft: removedToken)
        #expect(record.tokenDelta.nonFungibleTokenRemovals.contains(removalTokenData))
        #expect(record.tokenDelta.bitcoinCashLockedInTokenOutputDelta == 150)
    }
}

private extension TransactionHistoryTokenDeltaTests {
    enum TestError: Swift.Error {
        case unexpectedRequest
        case missingTransaction
    }
    
    struct AddressReaderStub: Network.AddressReadable {
        let historyByAddress: [String: [Network.TransactionHistoryEntry]]
        
        func fetchBalance(for address: String, tokenFilter: Network.TokenFilter) async throws -> Network.AddressBalance {
            throw TestError.unexpectedRequest
        }
        
        func fetchUnspentOutputs(for address: String, tokenFilter: Network.TokenFilter) async throws -> [Transaction.Output.Unspent] {
            []
        }
        
        func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [Network.TransactionHistoryEntry] {
            historyByAddress[address, default: []]
        }
        
        func fetchFirstUse(for address: String) async throws -> Network.AddressFirstUse? {
            nil
        }
        
        func fetchMempoolTransactions(for address: String) async throws -> [Network.TransactionHistoryEntry] {
            []
        }
        
        func fetchScriptHash(for address: String) async throws -> String {
            ""
        }
        
        func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<Network.AddressSubscriptionUpdate, any Swift.Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }
    
    struct TransactionReaderStub: Network.TransactionReadable {
        let rawTransactionsByHash: [Transaction.Hash: Data]
        
        func fetchRawTransaction(for transactionHash: Transaction.Hash) async throws -> Data {
            guard let data = rawTransactionsByHash[transactionHash] else {
                throw TestError.missingTransaction
            }
            return data
        }
    }
    
    func makeAddressBook() async throws -> Address.Book {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        return try await Address.Book(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                      purpose: .bip44,
                                      coinType: .bitcoinCash,
                                      account: .init(rawIndexInteger: 0),
                                      gapLimit: 2)
    }
    
    func makeExternalAddress() throws -> Address {
        let privateKey = try PrivateKey(data: Data(repeating: 0x03, count: 32))
        let publicKey = try PublicKey(privateKey: privateKey)
        return try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
    }
}
