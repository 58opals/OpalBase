// TransactionHistoryTokenDeltaValidator.swift

import Foundation
import OpalCrypto
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
        let previousHash = Self.hash(for: previousRawTransaction)
        
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
        let currentHash = Self.hash(for: currentRawTransaction)
        
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
        #expect(record.tokenDelta.bchLockedInTokenOutputDelta == 150)
    }

    @Test("skips coinbase inputs when computing token deltas")
    func tokenDeltaSkipsCoinbaseInputs() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let coinbaseInput = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
            previousTransactionOutputIndex: UInt32.max,
            unlockingScript: Data([0x01])
        )
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [coinbaseInput],
            outputs: [
                .init(value: 6_250_000_000, lockingScript: walletAddress.lockingScript.data)
            ],
            lockTime: 0
        )
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [:])
        )

        let tokenDelta = try await book.makeTokenDelta(
            from: transaction,
            transactionReader: transactionReader,
            walletScriptHashes: [walletAddress.makeScriptHash().hexadecimalString]
        )

        #expect(tokenDelta == .init())
    }

    @Test("throws instead of overflowing large fungible token deltas")
    func tokenDeltaOverflowThrows() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x44, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(
            category: category,
            amount: UInt64(Int64.max),
            nft: nil
        )
        let outputs = [
            OpalBase.Transaction.Output(value: 546, lockingScript: walletAddress.lockingScript.data, tokenData: tokenData),
            OpalBase.Transaction.Output(value: 546, lockingScript: walletAddress.lockingScript.data, tokenData: tokenData)
        ]
        let transaction = OpalBase.Transaction(version: 2, inputs: [], outputs: outputs, lockTime: 0)
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [:])
        )

        await #expect(throws: OpalBase.Address.Book.Error.tokenDeltaOverflow) {
            _ = try await book.makeTokenDelta(
                from: transaction,
                transactionReader: transactionReader,
                walletScriptHashes: [walletAddress.makeScriptHash().hexadecimalString]
            )
        }
    }

    @Test("nets unchanged non-fungible tokens moved between wallet outputs")
    func tokenDeltaNetsWalletInternalNonFungibleTokenMoves() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let changeEntry = await book.listEntries(for: .change).first
        let receivingAddress = try #require(receivingEntry?.address)
        let changeAddress = try #require(changeEntry?.address)
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x48, count: 32))
        let nonFungibleToken = try OpalBase.CashTokens.NFT(capability: .mutable, commitment: Data([0x01]))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: nil, nft: nonFungibleToken)
        let previousInput = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let previousTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [previousInput],
            outputs: [
                .init(value: 546, lockingScript: receivingAddress.lockingScript.data, tokenData: tokenData)
            ],
            lockTime: 0
        )
        let previousRawTransaction = try previousTransaction.encode()
        let previousHash = Self.hash(for: previousRawTransaction)
        let currentInput = OpalBase.Transaction.Input(
            previousTransactionHash: previousHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let currentTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [currentInput],
            outputs: [
                .init(value: 546, lockingScript: changeAddress.lockingScript.data, tokenData: tokenData)
            ],
            lockTime: 0
        )
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [
                previousHash: previousRawTransaction
            ])
        )

        let tokenDelta = try await book.makeTokenDelta(
            from: currentTransaction,
            transactionReader: transactionReader,
            walletScriptHashes: [
                receivingAddress.makeScriptHash().hexadecimalString,
                changeAddress.makeScriptHash().hexadecimalString
            ]
        )

        #expect(tokenDelta.nonFungibleTokenAdditions.isEmpty)
        #expect(tokenDelta.nonFungibleTokenRemovals.isEmpty)
        #expect(tokenDelta.bchLockedInTokenOutputDelta == 0)
    }

    @Test("throws instead of overflowing locked BCH token delta")
    func lockedBCHTokenDeltaOverflowThrows() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x45, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil)
        let output = OpalBase.Transaction.Output(
            value: UInt64(Int64.max) + 1,
            lockingScript: walletAddress.lockingScript.data,
            tokenData: tokenData
        )
        let transaction = OpalBase.Transaction(version: 2, inputs: [], outputs: [output], lockTime: 0)
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [:])
        )

        await #expect(throws: OpalBase.Address.Book.Error.tokenDeltaOverflow) {
            _ = try await book.makeTokenDelta(
                from: transaction,
                transactionReader: transactionReader,
                walletScriptHashes: [walletAddress.makeScriptHash().hexadecimalString]
            )
        }
    }

    @Test("throws when a spent previous output index is missing")
    func tokenDeltaThrowsWhenPreviousOutputIndexIsMissing() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let externalAddress = try makeExternalAddress()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x46, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil)

        let previousInput = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let previousTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [previousInput],
            outputs: [
                .init(value: 546, lockingScript: walletAddress.lockingScript.data, tokenData: tokenData)
            ],
            lockTime: 0
        )
        let previousRawTransaction = try previousTransaction.encode()
        let previousHash = Self.hash(for: previousRawTransaction)
        let currentInput = OpalBase.Transaction.Input(
            previousTransactionHash: previousHash,
            previousTransactionOutputIndex: 1,
            unlockingScript: Data()
        )
        let currentTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [currentInput],
            outputs: [
                .init(value: 546, lockingScript: externalAddress.lockingScript.data)
            ],
            lockTime: 0
        )
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [
                previousHash: previousRawTransaction
            ])
        )

        await #expect(throws: Data.Error.indexOutOfRange) {
            _ = try await book.makeTokenDelta(
                from: currentTransaction,
                transactionReader: transactionReader,
                walletScriptHashes: [walletAddress.makeScriptHash().hexadecimalString]
            )
        }
    }

    @Test("rejects previous transaction payloads with trailing bytes")
    func tokenDeltaRejectsPreviousTransactionTrailingBytes() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let externalAddress = try makeExternalAddress()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x47, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil)

        let previousInput = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let previousTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [previousInput],
            outputs: [
                .init(value: 546, lockingScript: walletAddress.lockingScript.data, tokenData: tokenData)
            ],
            lockTime: 0
        )
        let previousRawTransaction = try previousTransaction.encode() + Data([0x00])
        let previousHash = Self.hash(for: previousRawTransaction)
        let currentInput = OpalBase.Transaction.Input(
            previousTransactionHash: previousHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let currentTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [currentInput],
            outputs: [
                .init(value: 546, lockingScript: externalAddress.lockingScript.data)
            ],
            lockTime: 0
        )
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [
                previousHash: previousRawTransaction
            ])
        )

        await #expect(throws: OpalBase.Network.Error(
            reason: .decoding,
            message: "Transaction payload has trailing bytes"
        )) {
            _ = try await book.makeTokenDelta(
                from: currentTransaction,
                transactionReader: transactionReader,
                walletScriptHashes: [walletAddress.makeScriptHash().hexadecimalString]
            )
        }
    }

    @Test("rejects raw transaction payload hash mismatches")
    func tokenDeltaRejectsRawTransactionPayloadHashMismatches() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(value: 546, lockingScript: walletAddress.lockingScript.data)
            ],
            lockTime: 0
        )
        let rawTransactionData = try transaction.encode()
        let requestedHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x7A, count: 32))
        let actualHash = Self.hash(for: rawTransactionData)
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [
                requestedHash: rawTransactionData
            ])
        )

        await #expect(throws: OpalBase.Network.Error(
            reason: .protocolViolation,
            message: "Transaction payload hash mismatch",
            metadata: [
                "expected": requestedHash.reverseOrder.hexadecimalString,
                "actual": actualHash.reverseOrder.hexadecimalString
            ]
        )) {
            _ = try await book.makeTokenDelta(
                for: requestedHash,
                transactionReader: transactionReader,
                walletScriptHashes: [walletAddress.makeScriptHash().hexadecimalString]
            )
        }
    }

    @Test("rejects previous raw transaction payload hash mismatches")
    func tokenDeltaRejectsPreviousRawTransactionPayloadHashMismatches() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = await book.listEntries(for: .receiving).first
        let walletAddress = try #require(receivingEntry?.address)
        let previousTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(value: 546, lockingScript: walletAddress.lockingScript.data)
            ],
            lockTime: 0
        )
        let previousRawTransactionData = try previousTransaction.encode()
        let requestedPreviousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x7B, count: 32))
        let actualPreviousHash = Self.hash(for: previousRawTransactionData)
        #expect(requestedPreviousHash != actualPreviousHash)
        let currentTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: requestedPreviousHash,
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(value: 546, lockingScript: walletAddress.lockingScript.data)
            ],
            lockTime: 0
        )
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [
                requestedPreviousHash: previousRawTransactionData
            ])
        )

        await #expect(throws: OpalBase.Network.Error(
            reason: .protocolViolation,
            message: "Transaction payload hash mismatch",
            metadata: [
                "expected": requestedPreviousHash.reverseOrder.hexadecimalString,
                "actual": actualPreviousHash.reverseOrder.hexadecimalString
            ]
        )) {
            _ = try await book.makeTokenDelta(
                from: currentTransaction,
                transactionReader: transactionReader,
                walletScriptHashes: [walletAddress.makeScriptHash().hexadecimalString]
            )
        }
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
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        return try await OpalBase.Address.Book(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                      purpose: .bip44,
                                      coinType: .bitcoinCash,
                                      account: .init(rawIndexInteger: 0),
                                      gapLimit: 2)
    }
    
    func makeExternalAddress() throws -> OpalBase.Address {
        let publicKey = try OpalBase.Key.PublicKey(privateKeyData: Data(repeating: 0x03, count: 32))
        return try OpalBase.Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
    }

    static func hash(for data: Data) -> OpalBase.Transaction.Hash {
        OpalBase.Transaction.Hash(naturalOrder: OpalCryptoAdapter.hash256(data))
    }
}
