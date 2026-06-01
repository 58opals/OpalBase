// ClaimableStatusResolverValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Claimable status resolver", .tags(.unit))
struct ClaimableStatusResolverValidator {
    @Test("reports missing funding state")
    func reportsMissingFundingState() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in [] },
                fetchUnspent: { _, _ in [] }
            )
        )
        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 400
        )

        #expect(status.fundingState == .missing)
        #expect(status.confirmations == nil)
        #expect(status.tipHeight == nil)
        #expect(status.localStatus.allowsClaim)
    }

    @Test("rejects unconfirmed history returned for confirmed-only resolution")
    func rejectsUnconfirmedHistoryWhenExcluded() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: -1
                        )
                    ]
                },
                fetchUnspent: { _, _ in [] }
            )
        )

        do {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: false,
                currentBlockHeight: 400
            )
            Issue.record("Expected confirmed-only history to reject unconfirmed entries")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "Confirmed-only history response included an unconfirmed transaction")
        }
    }

    @Test("rejects duplicate transaction identifiers in history")
    func rejectsDuplicateTransactionIdentifiersInHistory() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: 490
                        ),
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: 491
                        )
                    ]
                },
                fetchUnspent: { _, _ in [] }
            )
        )

        do {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 400
            )
            Issue.record("Expected duplicate history identifiers to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "History response contained duplicate transaction identifiers")
        }
    }

    @Test("rejects malformed transaction identifiers in history")
    func rejectsMalformedTransactionIdentifiersInHistory() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        OpalBase.Network.TransactionHistoryEntry(
                            transactionIdentifier: "aa",
                            blockHeight: 490,
                            fee: nil
                        )
                    ]
                },
                fetchUnspent: { _, _ in [] }
            )
        )

        do {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 400
            )
            Issue.record("Expected malformed history identifiers to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "History response contained malformed transaction identifier")
        }
    }

    @Test("reports unspent funding state with confirmations")
    func reportsUnspentFundingStateWithConfirmations() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: envelope.fundingValue,
                lockingScript: envelope.contract.fundingLockingScriptData
            ),
            previousTransactionHash: envelope.fundingTransactionHash,
            previousTransactionOutputIndex: envelope.fundingOutputIndex
        )
        let confirmationStatus = OpalBase.Network.TransactionConfirmationStatus(
            transactionHash: envelope.fundingTransactionHash,
            transactionHeight: 490,
            tipHeight: 500,
            confirmations: 11
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: 490
                        )
                    ]
                },
                fetchUnspent: { _, _ in [unspentOutput] }
            ),
            transactionClient: .init(
                broadcastTransaction: { _ in "" },
                fetchConfirmations: { _ in 11 },
                fetchConfirmationStatus: { _ in confirmationStatus }
            )
        )
        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 400
        )

        #expect(status.fundingState == .unspent)
        #expect(status.confirmations == 11)
        #expect(status.tipHeight == 500)
        #expect(status.localStatus.allowsClaim)
    }

    @Test("rejects confirmation status height that disagrees with funding history")
    func rejectsConfirmationStatusHeightThatDisagreesWithFundingHistory() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: envelope.fundingValue,
                lockingScript: envelope.contract.fundingLockingScriptData
            ),
            previousTransactionHash: envelope.fundingTransactionHash,
            previousTransactionOutputIndex: envelope.fundingOutputIndex
        )
        let confirmationStatus = OpalBase.Network.TransactionConfirmationStatus(
            transactionHash: envelope.fundingTransactionHash,
            transactionHeight: 489,
            tipHeight: 500,
            confirmations: 12
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: 490
                        )
                    ]
                },
                fetchUnspent: { _, _ in [unspentOutput] }
            ),
            transactionClient: .init(
                broadcastTransaction: { _ in "" },
                fetchConfirmations: { _ in 12 },
                fetchConfirmationStatus: { _ in confirmationStatus }
            )
        )

        do {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 400
            )
            Issue.record("Expected mismatched confirmation height to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "Confirmation status height does not match funding history")
        }
    }

    @Test("rejects confirmation status for a different funding transaction")
    func rejectsMismatchedConfirmationStatusHash() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: envelope.fundingValue,
                lockingScript: envelope.contract.fundingLockingScriptData
            ),
            previousTransactionHash: envelope.fundingTransactionHash,
            previousTransactionOutputIndex: envelope.fundingOutputIndex
        )
        let mismatchedHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x45, count: 32)
        )
        let confirmationStatus = OpalBase.Network.TransactionConfirmationStatus(
            transactionHash: mismatchedHash,
            transactionHeight: 490,
            tipHeight: 500,
            confirmations: 11
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: 490
                        )
                    ]
                },
                fetchUnspent: { _, _ in [unspentOutput] }
            ),
            transactionClient: .init(
                broadcastTransaction: { _ in "" },
                fetchConfirmations: { _ in 11 },
                fetchConfirmationStatus: { _ in confirmationStatus }
            )
        )

        do {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 400
            )
            Issue.record("Expected mismatched confirmation status hash to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "Confirmation status hash mismatch")
        }
    }

    @Test("rejects confirmation status whose count does not match height and tip")
    func rejectsMismatchedConfirmationStatusCount() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: envelope.fundingValue,
                lockingScript: envelope.contract.fundingLockingScriptData
            ),
            previousTransactionHash: envelope.fundingTransactionHash,
            previousTransactionOutputIndex: envelope.fundingOutputIndex
        )
        let confirmationStatus = OpalBase.Network.TransactionConfirmationStatus(
            transactionHash: envelope.fundingTransactionHash,
            transactionHeight: 490,
            tipHeight: 500,
            confirmations: 1
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: 490
                        )
                    ]
                },
                fetchUnspent: { _, _ in [unspentOutput] }
            ),
            transactionClient: .init(
                broadcastTransaction: { _ in "" },
                fetchConfirmations: { _ in 1 },
                fetchConfirmationStatus: { _ in confirmationStatus }
            )
        )

        do {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 400
            )
            Issue.record("Expected mismatched confirmation status count to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "Confirmation status count does not match height and tip")
        }
    }

    @Test("rejects confirmation status with confirmed height but missing count")
    func rejectsConfirmedHeightWithoutConfirmationCount() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: envelope.fundingValue,
                lockingScript: envelope.contract.fundingLockingScriptData
            ),
            previousTransactionHash: envelope.fundingTransactionHash,
            previousTransactionOutputIndex: envelope.fundingOutputIndex
        )
        let confirmationStatus = OpalBase.Network.TransactionConfirmationStatus(
            transactionHash: envelope.fundingTransactionHash,
            transactionHeight: 490,
            tipHeight: 500,
            confirmations: nil
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: 490
                        )
                    ]
                },
                fetchUnspent: { _, _ in [unspentOutput] }
            ),
            transactionClient: .init(
                broadcastTransaction: { _ in "" },
                fetchConfirmations: { _ in 0 },
                fetchConfirmationStatus: { _ in confirmationStatus }
            )
        )

        do {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 400
            )
            Issue.record("Expected missing confirmation count to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "Confirmed transaction height requires confirmation count")
        }
    }

    @Test("rejects duplicate unspent funding outpoints")
    func rejectsDuplicateUnspentFundingOutpoints() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let validFundingOutput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: envelope.fundingValue,
                lockingScript: envelope.contract.fundingLockingScriptData
            ),
            previousTransactionHash: envelope.fundingTransactionHash,
            previousTransactionOutputIndex: envelope.fundingOutputIndex
        )
        let conflictingFundingOutput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: envelope.fundingValue + 1,
                lockingScript: envelope.contract.fundingLockingScriptData
            ),
            previousTransactionHash: envelope.fundingTransactionHash,
            previousTransactionOutputIndex: envelope.fundingOutputIndex
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: 490
                        )
                    ]
                },
                fetchUnspent: { _, _ in [validFundingOutput, conflictingFundingOutput] }
            )
        )

        do {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 400
            )
            Issue.record("Expected duplicate funding outpoints to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "Unspent output response contained duplicate outpoints")
        }
    }

    @Test("reports invalid funding state for token-bearing funding output")
    func reportsInvalidFundingStateForTokenBearingFundingOutput() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x42, count: 32)
        )
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil)
        let tokenBearingOutput = OpalBase.Transaction.Output.Unspent(
            value: envelope.fundingValue,
            lockingScript: envelope.contract.fundingLockingScriptData,
            tokenData: tokenData,
            previousTransactionHash: envelope.fundingTransactionHash,
            previousTransactionOutputIndex: envelope.fundingOutputIndex
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash
                        )
                    ]
                },
                fetchUnspent: { _, tokenFilter in
                    tokenFilter == .include ? [tokenBearingOutput] : []
                }
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 400
        )

        #expect(status.fundingState == .invalid)
    }

    @Test("reports unknown spent funding state without transaction reader")
    func reportsUnknownSpentFundingStateWithoutTransactionReader() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        ClaimableTestSupport.makeClaimableHistoryEntry(
                            transactionHash: envelope.fundingTransactionHash,
                            blockHeight: 490
                        )
                    ]
                },
                fetchUnspent: { _, _ in [] }
            )
        )
        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .spent(spendPath: .unknown))
        #expect(status.confirmations == nil)
        #expect(status.tipHeight == nil)
        #expect(status.localStatus.allowsRefund)
    }

    @Test("reports invalid funding state when referenced output mismatches contract")
    func reportsInvalidFundingStateWhenReferencedOutputMismatchesContract() async throws {
        let (draftEnvelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let invalidFundingOutput = OpalBase.Transaction.Output(
            value: draftEnvelope.fundingValue,
            lockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x45)
        )
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(
            for: draftEnvelope,
            output: invalidFundingOutput
        )
        let rawFundingTransaction = try fundingTransaction.encode()
        let envelope = try ClaimableTestSupport.replacingFundingTransactionHash(
            in: draftEnvelope,
            with: .init(naturalOrder: OpalCryptoAdapter.hash256(rawFundingTransaction))
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    )
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: rawFundingTransaction
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .invalid)
    }

    @Test("reports invalid funding state when raw funding transaction has trailing bytes")
    func reportsInvalidFundingStateWhenRawFundingTransactionHasTrailingBytes() async throws {
        let (draftEnvelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(for: draftEnvelope)
        var rawFundingTransaction = try fundingTransaction.encode()
        rawFundingTransaction.append(0x00)
        let envelope = try ClaimableTestSupport.replacingFundingTransactionHash(
            in: draftEnvelope,
            with: .init(naturalOrder: OpalCryptoAdapter.hash256(rawFundingTransaction))
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    )
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: rawFundingTransaction
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .invalid)
    }

    @Test("rejects raw funding transactions with mismatched payload hashes")
    func rejectsRawFundingTransactionsWithMismatchedPayloadHashes() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        var mismatchedRawFundingTransaction = try ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope).encode()
        mismatchedRawFundingTransaction[mismatchedRawFundingTransaction.count - 1] ^= 0x01
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    )
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: mismatchedRawFundingTransaction
                ]
            )
        )

        let failure = try await Self.captureNetworkError {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 700
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Transaction payload hash mismatch")
        #expect(failure.metadata["expected"] == envelope.fundingTransactionHash.reverseOrder.hexadecimalString)
        #expect(failure.metadata["actual"] == OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(mismatchedRawFundingTransaction)
        ).reverseOrder.hexadecimalString)
    }

    @Test("rejects spend path transactions with mismatched payload hashes")
    func rejectsSpendPathTransactionsWithMismatchedPayloadHashes() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope)
        let claimTransaction = try envelope.buildClaimTransaction(
            destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x51),
            currentBlockHeight: 499
        )
        let rawClaimTransaction = try claimTransaction.encode()
        let mismatchedClaimTransactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x51, count: 32)
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: mismatchedClaimTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    mismatchedClaimTransactionHash: rawClaimTransaction
                ]
            )
        )

        let failure = try await Self.captureNetworkError {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 700
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Transaction payload hash mismatch")
        #expect(failure.metadata["expected"] == mismatchedClaimTransactionHash.reverseOrder.hexadecimalString)
        #expect(failure.metadata["actual"] == ClaimableTestSupport.makeClaimableTransactionHash(
            from: rawClaimTransaction
        ).reverseOrder.hexadecimalString)
    }

    @Test("reports spend paths", arguments: SpendPathCase.allCases)
    func reportsSpendPath(_ spendPathCase: SpendPathCase) async throws {
        let (envelope, refundPrivateKey) = try ClaimableTestSupport.makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope)
        let spendTransaction = try spendPathCase.makeTransaction(
            for: envelope,
            refundPrivateKey: refundPrivateKey
        )
        let rawSpendTransaction = try spendTransaction.encode()
        let spendTransactionHash = ClaimableTestSupport.makeClaimableTransactionHash(from: rawSpendTransaction)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: spendTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    spendTransactionHash: rawSpendTransaction
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .spent(spendPath: spendPathCase.expectedSpendPath))
    }

    @Test("ignores spend path transactions with trailing bytes")
    func ignoresSpendPathTransactionsWithTrailingBytes() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope)
        let claimTransaction = try envelope.buildClaimTransaction(
            destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x51),
            currentBlockHeight: 499
        )
        var rawClaimTransaction = try claimTransaction.encode()
        rawClaimTransaction.append(0x00)
        let claimTransactionHash = ClaimableTestSupport.makeClaimableTransactionHash(from: rawClaimTransaction)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: claimTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    claimTransactionHash: rawClaimTransaction
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .spent(spendPath: .unknown))
    }

    @Test(
        "reports unknown spend path when matching spend has malformed unlocking script pushes",
        arguments: [
            (Data.push(Data()), Data.push(Data(count: 33)), UInt8(0x56)),
            (Data.push(Data(count: 65)), Data.push(Data()), UInt8(0x57)),
            (Data([ScriptOperationCode._PUSHDATA1.rawValue, 65]) + Data(count: 65), Data.push(Data(count: 33)), UInt8(0x58))
        ]
    )
    func reportUnknownSpendPathForMalformedUnlockingScriptPushes(
        _ malformedPushCase: (
            signatureWithHashTypePush: Data,
            compressedPublicKeyPush: Data,
            hashByte: UInt8
        )
    ) async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope)

        let malformedUnlockingScript = malformedPushCase.signatureWithHashTypePush
            + malformedPushCase.compressedPublicKeyPush
            + ScriptOperationCode._1.data
            + Data.push(envelope.contract.redeemScriptData)
        let malformedSpendTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: envelope.fundingTransactionHash,
                    previousTransactionOutputIndex: envelope.fundingOutputIndex,
                    unlockingScript: malformedUnlockingScript
                )
            ],
            outputs: [
                .init(
                    value: 1_000,
                    lockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: malformedPushCase.hashByte)
                )
            ],
            lockTime: 0
        )
        let rawMalformedSpendTransaction = try malformedSpendTransaction.encode()
        let malformedSpendTransactionHash = ClaimableTestSupport.makeClaimableTransactionHash(from: rawMalformedSpendTransaction)

        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: malformedSpendTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    malformedSpendTransactionHash: rawMalformedSpendTransaction
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .spent(spendPath: .unknown))
    }

    @Test("continues spend path scan past malformed unrelated history transaction")
    func continuesSpendPathScanPastMalformedUnrelatedHistoryTransaction() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope)
        let malformedTransactionData = Data([0x00])
        let malformedTransactionHash = ClaimableTestSupport.makeClaimableTransactionHash(from: malformedTransactionData)
        let claimTransaction = try envelope.buildClaimTransaction(
            destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x51),
            currentBlockHeight: 499
        )
        let rawClaimTransaction = try claimTransaction.encode()
        let claimTransactionHash = ClaimableTestSupport.makeClaimableTransactionHash(from: rawClaimTransaction)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: malformedTransactionHash),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: claimTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    malformedTransactionHash: malformedTransactionData,
                    claimTransactionHash: rawClaimTransaction
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .spent(spendPath: .claim))
    }

    @Test("continues spend path scan past unfetchable unrelated history transaction")
    func continuesSpendPathScanPastUnfetchableUnrelatedHistoryTransaction() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope)
        let unfetchableTransactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x50, count: 32)
        )
        let claimTransaction = try envelope.buildClaimTransaction(
            destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x51),
            currentBlockHeight: 499
        )
        let rawClaimTransaction = try claimTransaction.encode()
        let claimTransactionHash = ClaimableTestSupport.makeClaimableTransactionHash(from: rawClaimTransaction)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: unfetchableTransactionHash),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: claimTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    claimTransactionHash: rawClaimTransaction
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .spent(spendPath: .claim))
    }

    @Test("propagates cancellation while scanning spend path history")
    func propagatesTaskCancellationWhileScanningSpendPathHistory() async throws {
        let (envelope, resolver) = try makeResolverWithFailingSpendPathTransactionFetch(
            transactionFetchFailure: CancellationError(),
            failingTransactionHashByte: 0x50
        )

        await #expect(throws: CancellationError.self) {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 700
            )
        }
    }

    @Test("propagates translated network cancellation while scanning spend path history")
    func propagatesTranslatedNetworkCancellationWhileScanningSpendPathHistory() async throws {
        let networkCancellation = OpalBase.Network.Error(reason: .cancelled)
        let (envelope, resolver) = try makeResolverWithFailingSpendPathTransactionFetch(
            transactionFetchFailure: networkCancellation,
            failingTransactionHashByte: 0x55
        )

        await #expect(throws: networkCancellation) {
            _ = try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 700
            )
        }
    }

    private func makeResolverWithFailingSpendPathTransactionFetch(
        transactionFetchFailure: Swift.Error,
        failingTransactionHashByte: UInt8
    ) throws -> (envelope: OpalBase.Claimable.Envelope, resolver: OpalBase.Claimable.StatusResolver) {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransactionData = try ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope).encode()
        let failingTransactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: failingTransactionHashByte, count: 32)
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: failingTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: OpalBase.Network.TransactionReader { transactionHash in
                if transactionHash == envelope.fundingTransactionHash {
                    return fundingTransactionData
                }
                throw transactionFetchFailure
            }
        )

        return (envelope, resolver)
    }

    @Test("reports unknown spend path for ambiguous spend")
    func reportsUnknownSpendPathForAmbiguousSpend() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope)
        let ambiguousTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: envelope.fundingTransactionHash,
                    previousTransactionOutputIndex: envelope.fundingOutputIndex,
                    unlockingScript: Data([ScriptOperationCode._1.rawValue])
                )
            ],
            outputs: [
                .init(
                    value: 1_000,
                    lockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x53)
                )
            ],
            lockTime: 0
        )
        let rawAmbiguousTransaction = try ambiguousTransaction.encode()
        let ambiguousTransactionHash = ClaimableTestSupport.makeClaimableTransactionHash(from: rawAmbiguousTransaction)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: ambiguousTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    ambiguousTransactionHash: rawAmbiguousTransaction
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .spent(spendPath: .unknown))
    }

    @Test("continues spend path scan past ambiguous matching spend")
    func continuesSpendPathScanPastAmbiguousMatchingSpend() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransaction = ClaimableTestSupport.makeClaimableFundingTransaction(for: envelope)
        let ambiguousTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: envelope.fundingTransactionHash,
                    previousTransactionOutputIndex: envelope.fundingOutputIndex,
                    unlockingScript: Data([ScriptOperationCode._1.rawValue])
                )
            ],
            outputs: [
                .init(
                    value: 1_000,
                    lockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x53)
                )
            ],
            lockTime: 0
        )
        let rawAmbiguousTransaction = try ambiguousTransaction.encode()
        let ambiguousTransactionHash = ClaimableTestSupport.makeClaimableTransactionHash(from: rawAmbiguousTransaction)
        let claimTransaction = try envelope.buildClaimTransaction(
            destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x54),
            currentBlockHeight: 499
        )
        let rawClaimTransaction = try claimTransaction.encode()
        let claimTransactionHash = ClaimableTestSupport.makeClaimableTransactionHash(from: rawClaimTransaction)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: ClaimableTestSupport.makeClaimableScriptHashReader(
                history: [
                    ClaimableTestSupport.makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: ambiguousTransactionHash),
                    ClaimableTestSupport.makeClaimableHistoryEntry(transactionHash: claimTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: ClaimableTestSupport.makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    ambiguousTransactionHash: rawAmbiguousTransaction,
                    claimTransactionHash: rawClaimTransaction
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .spent(spendPath: .claim))
    }

    @Test("rejects resolver network mismatch")
    func rejectsResolverNetworkMismatch() async throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .mainnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in [] },
                fetchUnspent: { _, _ in [] }
            )
        )

        await #expect(
            throws: OpalBase.Claimable.Error.networkMismatch(
                expected: .mainnet,
                actual: .chipnet
            )
        ) {
            try await resolver.resolve(
                for: envelope,
                includeUnconfirmed: true,
                currentBlockHeight: 400
            )
        }
    }

    private enum NetworkErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    private static func captureNetworkError(
        _ work: () async throws -> Void
    ) async throws -> OpalBase.Network.Error {
        do {
            try await work()
            throw NetworkErrorCaptureFailure.didNotThrow
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch let failure as NetworkErrorCaptureFailure {
            throw failure
        } catch {
            throw NetworkErrorCaptureFailure.unexpected(error)
        }
    }

    enum SpendPathCase: CaseIterable, Sendable {
        case claim
        case refund

        var expectedSpendPath: OpalBase.Claimable.SpendPath {
            switch self {
            case .claim:
                return .claim
            case .refund:
                return .refund
            }
        }

        func makeTransaction(
            for envelope: OpalBase.Claimable.Envelope,
            refundPrivateKey: Data
        ) throws -> OpalBase.Transaction {
            switch self {
            case .claim:
                try envelope.buildClaimTransaction(
                    destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x51),
                    currentBlockHeight: 499
                )
            case .refund:
                try envelope.buildRefundTransaction(
                    refundPrivateKey: refundPrivateKey,
                    destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x52),
                    currentBlockHeight: 500
                )
            }
        }
    }
}
