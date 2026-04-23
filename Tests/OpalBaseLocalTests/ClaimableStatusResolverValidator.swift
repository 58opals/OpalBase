// ClaimableStatusResolverValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Claimable status resolver", .tags(.unit))
struct ClaimableStatusResolverValidator {
    @Test("reports missing funding state")
    func reportsMissingFundingState() async throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
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

    @Test("reports unspent funding state with confirmations")
    func reportsUnspentFundingStateWithConfirmations() async throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
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
                        makeClaimableHistoryEntry(
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

    @Test("reports unknown spent funding state without transaction reader")
    func reportsUnknownSpentFundingStateWithoutTransactionReader() async throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: .init(
                fetchHistory: { _, _ in
                    [
                        makeClaimableHistoryEntry(
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
        let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
        let invalidFundingOutput = OpalBase.Transaction.Output(
            value: envelope.fundingValue,
            lockingScript: makeClaimableDestinationLockingScript(fillByte: 0x45)
        )
        let fundingTransaction = makeClaimableFundingTransaction(
            for: envelope,
            output: invalidFundingOutput
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: makeClaimableScriptHashReader(
                history: [
                    makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    )
                ],
                unspentOutputs: []
            ),
            transactionReader: makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode()
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

    @Test("reports claim spend path")
    func reportsClaimSpendPath() async throws {
        let (envelope, _) = try makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransaction = makeClaimableFundingTransaction(for: envelope)
        let claimTransaction = try envelope.buildClaimTransaction(
            destinationLockingScript: makeClaimableDestinationLockingScript(fillByte: 0x51),
            currentBlockHeight: 499
        )
        let claimTransactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x51, count: 32)
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: makeClaimableScriptHashReader(
                history: [
                    makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    makeClaimableHistoryEntry(transactionHash: claimTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    claimTransactionHash: try claimTransaction.encode()
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

    @Test("reports refund spend path")
    func reportsRefundSpendPath() async throws {
        let (envelope, refundPrivateKey) = try makeClaimableEnvelope(
            network: .chipnet,
            expiryBlockHeight: 500
        )
        let fundingTransaction = makeClaimableFundingTransaction(for: envelope)
        let refundTransaction = try envelope.buildRefundTransaction(
            refundPrivateKey: refundPrivateKey,
            destinationLockingScript: makeClaimableDestinationLockingScript(fillByte: 0x52),
            currentBlockHeight: 500
        )
        let refundTransactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x52, count: 32)
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: makeClaimableScriptHashReader(
                history: [
                    makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    makeClaimableHistoryEntry(transactionHash: refundTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    refundTransactionHash: try refundTransaction.encode()
                ]
            )
        )

        let status = try await resolver.resolve(
            for: envelope,
            includeUnconfirmed: true,
            currentBlockHeight: 700
        )

        #expect(status.fundingState == .spent(spendPath: .refund))
    }

    @Test("reports unknown spend path for ambiguous spend")
    func reportsUnknownSpendPathForAmbiguousSpend() async throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
        let fundingTransaction = makeClaimableFundingTransaction(for: envelope)
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
                    lockingScript: makeClaimableDestinationLockingScript(fillByte: 0x53)
                )
            ],
            lockTime: 0
        )
        let ambiguousTransactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x53, count: 32)
        )
        let resolver = OpalBase.Claimable.StatusResolver(
            network: .chipnet,
            scriptHashReader: makeClaimableScriptHashReader(
                history: [
                    makeClaimableHistoryEntry(
                        transactionHash: envelope.fundingTransactionHash
                    ),
                    makeClaimableHistoryEntry(transactionHash: ambiguousTransactionHash)
                ],
                unspentOutputs: []
            ),
            transactionReader: makeClaimableTransactionReader(
                rawTransactionsByHash: [
                    envelope.fundingTransactionHash: try fundingTransaction.encode(),
                    ambiguousTransactionHash: try ambiguousTransaction.encode()
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

    @Test("rejects resolver network mismatch")
    func rejectsResolverNetworkMismatch() async throws {
        let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
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
}
