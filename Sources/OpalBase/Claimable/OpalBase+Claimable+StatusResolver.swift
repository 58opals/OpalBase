// OpalBase+Claimable+StatusResolver.swift

import Foundation

extension _OpalBase.Claimable {
    public struct StatusResolver {
        private let network: OpalBase.Network.Environment
        private let scriptHashReader: OpalBase.Network.ScriptHashReader
        private let transactionClient: OpalBase.Network.TransactionClient?
        private let transactionReader: OpalBase.Network.TransactionReader?

        public init(
            network: OpalBase.Network.Environment,
            scriptHashReader: OpalBase.Network.ScriptHashReader,
            transactionClient: OpalBase.Network.TransactionClient? = nil,
            transactionReader: OpalBase.Network.TransactionReader? = nil
        ) {
            self.network = network
            self.scriptHashReader = scriptHashReader
            self.transactionClient = transactionClient
            self.transactionReader = transactionReader
        }

        public func resolve(
            for envelope: OpalBase.Claimable.Envelope,
            includeUnconfirmed: Bool,
            currentBlockHeight: UInt32
        ) async throws -> OpalBase.Claimable.NetworkStatus {
            guard envelope.contract.network == network else {
                throw OpalBase.Claimable.Error.networkMismatch(
                    expected: network,
                    actual: envelope.contract.network
                )
            }

            let scriptHashHex = makeClaimableQueryScriptHashHex(
                from: envelope.contract.fundingLockingScriptData
            )
            let history = try await scriptHashReader.fetchHistory(
                forScriptHash: scriptHashHex,
                includeUnconfirmed: includeUnconfirmed
            )
            let unspentOutputs = try await scriptHashReader.fetchUnspent(
                forScriptHash: scriptHashHex,
                tokenFilter: .exclude
            )

            let fundingState = try await makeFundingState(
                for: envelope,
                history: history,
                unspentOutputs: unspentOutputs
            )

            var confirmations: UInt?
            var tipHeight: UInt64?
            if fundingState != .missing, let transactionClient {
                let confirmationStatus = try await transactionClient.fetchConfirmationStatus(
                    for: envelope.fundingTransactionHash
                )
                confirmations = confirmationStatus.confirmations
                tipHeight = confirmationStatus.tipHeight
            }

            return OpalBase.Claimable.NetworkStatus(
                localStatus: envelope.makeLocalStatus(currentBlockHeight: currentBlockHeight),
                fundingState: fundingState,
                confirmations: confirmations,
                tipHeight: tipHeight
            )
        }
    }
}

extension _OpalBase.Claimable.StatusResolver: Sendable {}

private extension _OpalBase.Claimable.StatusResolver {
    func makeFundingState(
        for envelope: OpalBase.Claimable.Envelope,
        history: [OpalBase.Network.TransactionHistoryEntry],
        unspentOutputs: [OpalBase.Transaction.Output.Unspent]
    ) async throws -> OpalBase.Claimable.FundingState {
        if let unspentOutput = unspentOutputs.first(where: { $0.matchesClaimableOutpoint(envelope) }) {
            return unspentOutput.matchesClaimableFunding(envelope) ? .unspent : .invalid
        }

        guard history.contains(where: { $0.matchesClaimableFundingTransaction(envelope) }) else {
            return .missing
        }

        guard let transactionReader else {
            return .spent(spendPath: .unknown)
        }

        let rawFundingTransactionData = try await transactionReader.fetchRawTransaction(
            for: envelope.fundingTransactionHash
        )
        guard let fundingTransaction = try? OpalBase.Transaction.decode(
            from: rawFundingTransactionData
        ).transaction else {
            return .invalid
        }
        guard fundingTransaction.hasClaimableFundingOutput(envelope) else {
            return .invalid
        }

        let spendPath = try await makeSpendPath(
            for: envelope,
            history: history,
            transactionReader: transactionReader
        )
        return .spent(spendPath: spendPath)
    }

    func makeSpendPath(
        for envelope: OpalBase.Claimable.Envelope,
        history: [OpalBase.Network.TransactionHistoryEntry],
        transactionReader: OpalBase.Network.TransactionReader
    ) async throws -> OpalBase.Claimable.SpendPath {
        for entry in history where !entry.matchesClaimableFundingTransaction(envelope) {
            guard let transactionHash = try? entry.makeClaimableTransactionHash() else {
                continue
            }
            let rawTransactionData = try await transactionReader.fetchRawTransaction(
                for: transactionHash
            )
            guard let transaction = try? OpalBase.Transaction.decode(
                from: rawTransactionData
            ).transaction else {
                return .unknown
            }

            for input in transaction.inputs where input.matchesClaimableOutpoint(envelope) {
                return makeClaimableSpendPath(
                    from: input.unlockingScript,
                    expectedRedeemScriptData: envelope.contract.redeemScriptData
                ) ?? .unknown
            }
        }

        return .unknown
    }
}

private extension OpalBase.Network.TransactionHistoryEntry {
    func matchesClaimableFundingTransaction(_ envelope: OpalBase.Claimable.Envelope) -> Bool {
        transactionIdentifier.compare(
            envelope.fundingTransactionHash.reverseOrder.hexadecimalString,
            options: .caseInsensitive
        ) == .orderedSame
    }

    func makeClaimableTransactionHash() throws -> OpalBase.Transaction.Hash {
        try OpalBase.Network.decodeTransactionHash(from: transactionIdentifier)
    }
}

private extension OpalBase.Transaction.Output.Unspent {
    func matchesClaimableOutpoint(_ envelope: OpalBase.Claimable.Envelope) -> Bool {
        previousTransactionHash == envelope.fundingTransactionHash
            && previousTransactionOutputIndex == envelope.fundingOutputIndex
    }

    func matchesClaimableFunding(_ envelope: OpalBase.Claimable.Envelope) -> Bool {
        matchesClaimableOutpoint(envelope)
            && value == envelope.fundingValue
            && lockingScript == envelope.contract.fundingLockingScriptData
            && tokenData == nil
    }
}

private extension OpalBase.Transaction {
    func hasClaimableFundingOutput(_ envelope: OpalBase.Claimable.Envelope) -> Bool {
        guard outputs.indices.contains(Int(envelope.fundingOutputIndex)) else {
            return false
        }

        let output = outputs[Int(envelope.fundingOutputIndex)]
        return output.value == envelope.fundingValue
            && output.lockingScript == envelope.contract.fundingLockingScriptData
            && output.tokenData == nil
    }
}

private extension OpalBase.Transaction.Input {
    func matchesClaimableOutpoint(_ envelope: OpalBase.Claimable.Envelope) -> Bool {
        previousTransactionHash == envelope.fundingTransactionHash
            && previousTransactionOutputIndex == envelope.fundingOutputIndex
    }
}
