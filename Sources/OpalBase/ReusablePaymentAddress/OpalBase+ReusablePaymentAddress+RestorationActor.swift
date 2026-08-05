// OpalBase+ReusablePaymentAddress+RestorationActor.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// Long-lived owner of one authorized Cash Code restoration lifecycle.
    ///
    /// Only one asynchronous lifecycle operation may be in flight. Overlapping
    /// calls fail with `restorationOperationInProgress`. Each confirmed height
    /// window, mempool snapshot, and reorganization rollback is committed as
    /// one complete durable-state replacement.
    public actor RestorationActor {
        private let address: OpalBase.ReusablePaymentAddress
        private let transport: Transport
        private let persistence: StatePersistence
        private let scanSigningKey: OpalBase.Key.SigningKey
        private let spendSigningKey: OpalBase.Key.SigningKey
        private let matcher = Matcher()

        private var state: RestorationState
        private var isOperationActive = false

        init(
            address: OpalBase.ReusablePaymentAddress,
            transport: Transport,
            persistence: StatePersistence,
            scanSigningKey: OpalBase.Key.SigningKey,
            spendSigningKey: OpalBase.Key.SigningKey,
            state: RestorationState
        ) {
            self.address = address
            self.transport = transport
            self.persistence = persistence
            self.scanSigningKey = scanSigningKey
            self.spendSigningKey = spendSigningKey
            self.state = state
        }

        /// Current durable-state snapshot.
        public var stateSnapshot: RestorationState {
            state
        }

        /// Restores confirmed history through a half-open upper bound.
        ///
        /// Cancellation or any failure before a complete window commit leaves
        /// that window and its cursor advancement unapplied. A successful
        /// return contains the last durably committed state.
        @discardableResult
        public func restoreConfirmed(
            upToHeightExclusive upperBound: UInt,
            windowSize: UInt
        ) async throws -> RestorationState {
            try beginOperation()
            defer { finishOperation() }

            guard windowSize > 0 else {
                throw Error.invalidWindowSize
            }
            guard upperBound >= state.nextUnscannedHeight else {
                throw Error.invalidHeightRange
            }

            while state.nextUnscannedHeight < upperBound {
                try Task.checkCancellation()
                let lowerBound = state.nextUnscannedHeight
                let remaining = upperBound - lowerBound
                let windowUpperBound = lowerBound + min(windowSize, remaining)
                let heights = lowerBound..<windowUpperBound
                let references = try await transport.candidates
                    .fetchConfirmedTransactionReferences(
                        matching: address.filterPrefix,
                        in: heights
                    )
                try Task.checkCancellation()
                let candidates = try deduplicateConfirmedReferences(
                    references,
                    in: heights
                )
                let matches = try await loadConfirmedMatches(candidates)
                try Task.checkCancellation()
                try await commitConfirmedWindow(
                    matches,
                    candidateTransactionHashes: Set(
                        candidates.map(\.transactionHash)
                    ),
                    nextUnscannedHeight: windowUpperBound
                )
            }

            return state
        }

        /// Atomically replaces unconfirmed matches with the backend's current
        /// verified mempool snapshot. Confirmed outpoints always take
        /// precedence, and entries absent from the new snapshot are removed.
        @discardableResult
        public func refreshMempool() async throws -> RestorationState {
            try beginOperation()
            defer { finishOperation() }

            try Task.checkCancellation()
            let references = try await transport.candidates
                .fetchMempoolTransactionReferences(
                    matching: address.filterPrefix
                )
            try Task.checkCancellation()
            let candidates = try deduplicateMempoolReferences(references)
            let loadedMatches = try await loadMempoolMatches(candidates)
            try Task.checkCancellation()

            let confirmedOutpoints = Set(
                state.confirmedMatches.map(\.output.outpoint)
            )
            let normalized = normalizeMempoolMatches(loadedMatches)
                .filter { !confirmedOutpoints.contains($0.output.outpoint) }
            guard normalized != state.mempoolMatches else {
                return state
            }

            let nextState = try state.makeReplacement(
                revision: try makeNextRevision(),
                mempoolMatches: normalized
            )
            try await commit(nextState)
            return state
        }

        /// Applies one trusted chain-reorganization event and rewinds the
        /// confirmed cursor to the first affected height, bounded by the
        /// configured restore start and current cursor. A caller can then replay with
        /// `restoreConfirmed(upToHeightExclusive:windowSize:)`.
        @discardableResult
        public func applyReorganization(
            eventIdentifier: String,
            firstAffectedHeight: UInt
        ) async throws -> RestorationState {
            try beginOperation()
            defer { finishOperation() }

            guard !eventIdentifier.isEmpty,
                  eventIdentifier.utf8.count <= 1_024
            else {
                throw Error.invalidPersistentState
            }
            if let prior = state.reorganizationHistory.first(where: {
                $0.eventIdentifier == eventIdentifier
            }) {
                guard prior.firstAffectedHeight == firstAffectedHeight else {
                    throw Error.candidateReferenceConflict
                }
                return state
            }

            try Task.checkCancellation()
            let previousNextUnscannedHeight = state.nextUnscannedHeight
            let safeHeight = max(
                state.restoreStartHeight,
                firstAffectedHeight
            )
            let rollbackHeight = min(
                previousNextUnscannedHeight,
                safeHeight
            )
            let retainedMatches = state.confirmedMatches.filter {
                $0.blockHeight < rollbackHeight
            }
            let metadata = ReorganizationMetadata(
                eventIdentifier: eventIdentifier,
                firstAffectedHeight: firstAffectedHeight,
                rollbackHeight: rollbackHeight,
                previousNextUnscannedHeight: previousNextUnscannedHeight
            )
            let reorganizationHistory = Array(
                (state.reorganizationHistory + [metadata]).suffix(64)
            )
            let nextState = try state.makeReplacement(
                revision: try makeNextRevision(),
                nextUnscannedHeight: rollbackHeight,
                confirmedMatches: retainedMatches,
                reorganizationHistory: reorganizationHistory
            )
            try Task.checkCancellation()
            try await commit(nextState)
            return state
        }

        /// Rederives the opaque receiving authority for a retained matched
        /// output. No private-key representation is returned.
        public func rederiveReceivingCapability(
            for outpoint: OpalBase.Transaction.Outpoint
        ) throws -> ReceivingCapability {
            guard !isOperationActive else {
                throw Error.restorationOperationInProgress
            }
            return try makeReceivingCapability(for: outpoint)
        }

        private func makeReceivingCapability(
            for outpoint: OpalBase.Transaction.Outpoint
        ) throws -> ReceivingCapability {
            let derivation = try requireDerivation(for: outpoint)
            do {
                let sharedPointDigest = try CashCodeDerivation
                    .makeSharedPointDigest(
                        signingKey: scanSigningKey,
                        publicKey: derivation.senderPublicKey
                    )
                let signingKey = try CashCodeDerivation.deriveSigningKey(
                    from: spendSigningKey,
                    sharedPointDigest: sharedPointDigest,
                    outpoint: derivation.senderOutpoint
                )
                guard signingKey.publicKey == derivation.receivingPublicKey
                else {
                    throw Error.invalidPersistentState
                }
                return ReceivingCapability(
                    outpoint: outpoint,
                    signingKey: signingKey
                )
            } catch let error as Error {
                throw error
            } catch {
                throw Error.childKeyDerivationFailed
            }
        }

        /// Verifies that a retained match is currently unspent with the exact
        /// persisted value, locking script, and CashToken payload.
        public func confirmUnspentOutput(
            for outpoint: OpalBase.Transaction.Outpoint,
            using reader: OpalBase.Network.AddressReader
        ) async throws -> SpendableOutput {
            try beginOperation()
            defer { finishOperation() }

            let matchedOutput = try requireMatchedOutput(for: outpoint)
            let capability = try makeReceivingCapability(for: outpoint)
            let script = try OpalBase.Script.decode(
                lockingScript: matchedOutput.lockingScript
            )
            let queriedAddress = try OpalBase.Address(
                script: script,
                format: matchedOutput.tokenData == nil
                    ? .standard
                    : .tokenAware,
                network: address.network
            )
            let returnedOutputs = try await reader.fetchUnspentOutputs(
                for: queriedAddress.generateString(withPrefix: true),
                tokenFilter: .include
            )
            try Task.checkCancellation()
            let sameOutpoint = returnedOutputs.filter {
                OpalBase.Transaction.Outpoint($0) == outpoint
            }
            guard !sameOutpoint.isEmpty else {
                throw Error.unspentOutputNotFound
            }
            let expected = OpalBase.Transaction.Output.Unspent(
                output: matchedOutput.transactionOutput,
                previousTransactionHash: matchedOutput.transactionHash,
                previousTransactionOutputIndex: matchedOutput.outputIndex
            )
            guard sameOutpoint.allSatisfy({
                $0.hasSameOutpointAndPayload(as: expected)
            }) else {
                throw Error.unspentOutputPayloadMismatch
            }
            return SpendableOutput(
                unspentOutput: expected,
                capability: capability
            )
        }

        /// Prepares an opaque-key spend plan for verified Cash Code UTXOs.
        public func prepareSpend(
            spending outputs: [SpendableOutput],
            recipientOutputs: [OpalBase.Transaction.Output],
            changeOutput: OpalBase.Transaction.Output,
            feeRate: UInt64,
            shouldAllowDustDonation: Bool = false
        ) throws -> ReceivedOutputSpendPlan {
            guard !isOperationActive else {
                throw Error.restorationOperationInProgress
            }
            for output in outputs {
                let retained = try requireMatchedOutput(
                    for: .init(output.unspentOutput)
                )
                let expected = OpalBase.Transaction.Output.Unspent(
                    output: retained.transactionOutput,
                    previousTransactionHash: retained.transactionHash,
                    previousTransactionOutputIndex: retained.outputIndex
                )
                guard output.unspentOutput.hasSameOutpointAndPayload(
                    as: expected
                ),
                output.capability.outpoint == retained.outpoint,
                output.capability.publicKey == output.receivingPublicKey
                else {
                    throw Error.unspentOutputPayloadMismatch
                }
            }
            return try ReceivedOutputSpendPlan(
                spendableOutputs: outputs,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                feeRate: feeRate,
                shouldAllowDustDonation: shouldAllowDustDonation
            )
        }

        private func beginOperation() throws {
            guard !isOperationActive else {
                throw Error.restorationOperationInProgress
            }
            isOperationActive = true
        }

        private func requireMatchedOutput(
            for outpoint: OpalBase.Transaction.Outpoint
        ) throws -> MatchedOutput {
            if let match = state.confirmedMatches.first(where: {
                $0.output.outpoint == outpoint
            }) {
                return match.output
            }
            if let match = state.mempoolMatches.first(where: {
                $0.output.outpoint == outpoint
            }) {
                return match.output
            }
            throw Error.matchedOutputNotFound
        }

        private func requireDerivation(
            for outpoint: OpalBase.Transaction.Outpoint
        ) throws -> DerivationContext {
            if let match = state.confirmedMatches.first(where: {
                $0.output.outpoint == outpoint
            }) {
                return match.derivation
            }
            if let match = state.mempoolMatches.first(where: {
                $0.output.outpoint == outpoint
            }) {
                return match.derivation
            }
            throw Error.matchedOutputNotFound
        }

        private func finishOperation() {
            isOperationActive = false
        }

        private func makeNextRevision() throws -> UInt64 {
            let (revision, overflow) = state.revision
                .addingReportingOverflow(1)
            guard !overflow else {
                throw Error.stateRevisionConflict
            }
            return revision
        }

        private func commit(_ nextState: RestorationState) async throws {
            try nextState.validate()
            try nextState.requireCapabilities(
                scanSigningKey: scanSigningKey,
                spendSigningKey: spendSigningKey
            )
            try await persistence.saveState(
                nextState,
                replacingRevision: state.revision
            )
            state = nextState
        }

        private func deduplicateConfirmedReferences(
            _ references: [ConfirmedTransactionReference],
            in heights: Range<UInt>
        ) throws -> [ConfirmedTransactionReference] {
            var byHash: [OpalBase.Transaction.Hash: ConfirmedTransactionReference]
                = .init()
            for reference in references {
                guard heights.contains(reference.blockHeight) else {
                    throw Error.candidateOutsideRequestedWindow
                }
                if let prior = byHash[reference.transactionHash],
                   prior != reference {
                    throw Error.candidateReferenceConflict
                }
                byHash[reference.transactionHash] = reference
            }
            return byHash.values.sorted(by: compareConfirmedReferences)
        }

        private func compareConfirmedReferences(
            _ left: ConfirmedTransactionReference,
            _ right: ConfirmedTransactionReference
        ) -> Bool {
            if left.blockHeight != right.blockHeight {
                return left.blockHeight < right.blockHeight
            }
            return left.transactionHash.reverseOrder.lexicographicallyPrecedes(
                right.transactionHash.reverseOrder
            )
        }

        private func deduplicateMempoolReferences(
            _ references: [MempoolTransactionReference]
        ) throws -> [MempoolTransactionReference] {
            var byHash: [OpalBase.Transaction.Hash: MempoolTransactionReference]
                = .init()
            for reference in references {
                if let prior = byHash[reference.transactionHash],
                   prior != reference {
                    throw Error.candidateReferenceConflict
                }
                byHash[reference.transactionHash] = reference
            }
            return byHash.values.sorted {
                $0.transactionHash.reverseOrder.lexicographicallyPrecedes(
                    $1.transactionHash.reverseOrder
                )
            }
        }

        private func loadConfirmedMatches(
            _ references: [ConfirmedTransactionReference]
        ) async throws -> [ConfirmedMatch] {
            var results: [ConfirmedMatch] = .init()
            for reference in references {
                try Task.checkCancellation()
                let matches = try await loadMatches(
                    transactionHash: reference.transactionHash
                )
                results.append(contentsOf: matches.map {
                    ConfirmedMatch(
                        blockHeight: reference.blockHeight,
                        match: $0
                    )
                })
            }
            return normalizeConfirmedMatches(results)
        }

        private func loadMempoolMatches(
            _ references: [MempoolTransactionReference]
        ) async throws -> [MempoolMatch] {
            var results: [MempoolMatch] = .init()
            for reference in references {
                try Task.checkCancellation()
                let matches = try await loadMatches(
                    transactionHash: reference.transactionHash
                )
                results.append(contentsOf: matches.map {
                    MempoolMatch(reference: reference, match: $0)
                })
            }
            return normalizeMempoolMatches(results)
        }

        private func loadMatches(
            transactionHash: OpalBase.Transaction.Hash
        ) async throws -> [Match] {
            let serializedTransaction = try await transport.transactions
                .fetchRawTransaction(for: transactionHash)
            try Task.checkCancellation()
            let actualHash = OpalBase.Transaction.Hash(
                naturalOrder: OpalCryptoAdapter.hash256(serializedTransaction)
            )
            guard actualHash == transactionHash else {
                throw Error.transactionHashMismatch
            }
            return try matcher.matches(
                in: serializedTransaction,
                for: address,
                scanSigningKey: scanSigningKey,
                spendSigningKey: spendSigningKey
            )
        }

        private func commitConfirmedWindow(
            _ matches: [ConfirmedMatch],
            candidateTransactionHashes: Set<OpalBase.Transaction.Hash>,
            nextUnscannedHeight: UInt
        ) async throws {
            var byOutpoint = Dictionary(
                uniqueKeysWithValues: state.confirmedMatches.map {
                    ($0.output.outpoint, $0)
                }
            )
            for match in matches {
                if let prior = byOutpoint[match.output.outpoint],
                   prior.blockHeight != match.blockHeight {
                    throw Error.candidateReferenceConflict
                }
                byOutpoint[match.output.outpoint] = selectPreferredConfirmedMatch(
                    match,
                    over: byOutpoint[match.output.outpoint]
                )
            }
            let confirmedMatches = byOutpoint.values.sorted(
                by: compareConfirmedMatches
            )
            let mempoolMatches = state.mempoolMatches.filter {
                !candidateTransactionHashes.contains(
                    $0.output.transactionHash
                )
            }
            let nextState = try state.makeReplacement(
                revision: try makeNextRevision(),
                nextUnscannedHeight: nextUnscannedHeight,
                confirmedMatches: confirmedMatches,
                mempoolMatches: mempoolMatches
            )
            try await commit(nextState)
        }

        private func normalizeConfirmedMatches(
            _ matches: [ConfirmedMatch]
        ) -> [ConfirmedMatch] {
            var byOutpoint: [OpalBase.Transaction.Outpoint: ConfirmedMatch]
                = .init()
            for match in matches {
                byOutpoint[match.output.outpoint] = selectPreferredConfirmedMatch(
                    match,
                    over: byOutpoint[match.output.outpoint]
                )
            }
            return byOutpoint.values.sorted(by: compareConfirmedMatches)
        }

        private func selectPreferredConfirmedMatch(
            _ candidate: ConfirmedMatch,
            over prior: ConfirmedMatch?
        ) -> ConfirmedMatch {
            guard let prior else { return candidate }
            if candidate.derivation.qualifyingInputIndex
                != prior.derivation.qualifyingInputIndex {
                return candidate.derivation.qualifyingInputIndex
                    < prior.derivation.qualifyingInputIndex
                    ? candidate
                    : prior
            }
            return candidate.derivation.senderPublicKey.compressedData
                .lexicographicallyPrecedes(
                    prior.derivation.senderPublicKey.compressedData
                ) ? candidate : prior
        }

        private func compareConfirmedMatches(
            _ left: ConfirmedMatch,
            _ right: ConfirmedMatch
        ) -> Bool {
            if left.blockHeight != right.blockHeight {
                return left.blockHeight < right.blockHeight
            }
            return compareMatchedOutputs(
                left.output,
                left.derivation,
                right.output,
                right.derivation
            )
        }

        private func normalizeMempoolMatches(
            _ matches: [MempoolMatch]
        ) -> [MempoolMatch] {
            var byOutpoint: [OpalBase.Transaction.Outpoint: MempoolMatch]
                = .init()
            for match in matches {
                guard let prior = byOutpoint[match.output.outpoint] else {
                    byOutpoint[match.output.outpoint] = match
                    continue
                }
                if match.derivation.qualifyingInputIndex
                    < prior.derivation.qualifyingInputIndex {
                    byOutpoint[match.output.outpoint] = match
                }
            }
            return byOutpoint.values.sorted {
                compareMatchedOutputs(
                    $0.output,
                    $0.derivation,
                    $1.output,
                    $1.derivation
                )
            }
        }

        private func compareMatchedOutputs(
            _ leftOutput: MatchedOutput,
            _ leftDerivation: DerivationContext,
            _ rightOutput: MatchedOutput,
            _ rightDerivation: DerivationContext
        ) -> Bool {
            if leftOutput.transactionHash != rightOutput.transactionHash {
                return leftOutput.transactionHash.reverseOrder
                    .lexicographicallyPrecedes(
                        rightOutput.transactionHash.reverseOrder
                    )
            }
            if leftOutput.outputIndex != rightOutput.outputIndex {
                return leftOutput.outputIndex < rightOutput.outputIndex
            }
            return leftDerivation.qualifyingInputIndex
                < rightDerivation.qualifyingInputIndex
        }
    }
}
