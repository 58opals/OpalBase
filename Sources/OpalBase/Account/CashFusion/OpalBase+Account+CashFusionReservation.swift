// OpalBase+Account+CashFusionReservation.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    actor CashFusionRoundReservationRegistry {
        private var roundReservationByIdentifier: [OpalFusion.Round.Identifier: CashFusionRoundReservation] = [:]
        private var completedLocalOutputsByRoundIdentifier: [
            OpalFusion.Round.Identifier: [OpalBase.Transaction.Output.Unspent]
        ] = [:]

        func roundReservation(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) -> CashFusionRoundReservation? {
            roundReservationByIdentifier[roundIdentifier]
        }

        func insert(
            _ roundReservation: CashFusionRoundReservation
        ) -> (roundReservation: CashFusionRoundReservation, inserted: Bool) {
            if let existing = roundReservationByIdentifier[roundReservation.roundIdentifier] {
                return (existing, false)
            }

            roundReservationByIdentifier[roundReservation.roundIdentifier] = roundReservation
            return (roundReservation, true)
        }

        func drainRoundReservations() -> [CashFusionRoundReservation] {
            let roundReservations = Array(roundReservationByIdentifier.values)
            roundReservationByIdentifier.removeAll()
            return roundReservations
        }

        func recordCompletedLocalOutputs(
            _ completedLocalOutputs: [OpalBase.Transaction.Output.Unspent],
            for roundIdentifier: OpalFusion.Round.Identifier
        ) {
            completedLocalOutputsByRoundIdentifier[roundIdentifier] = completedLocalOutputs
        }

        func completedLocalOutputs(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) -> [OpalBase.Transaction.Output.Unspent] {
            completedLocalOutputsByRoundIdentifier[roundIdentifier] ?? []
        }

        func clearCompletedLocalOutputs() {
            completedLocalOutputsByRoundIdentifier.removeAll()
        }
    }

    struct CashFusionReservation: Sendable {
        struct ReservedInput: Sendable {
            let unspentOutput: OpalBase.Transaction.Output.Unspent
            let privateKey: Data
            let compressedPublicKey: Data
            let participantInput: OpalFusion.Host.ParticipantInput

            init(
                unspentOutput: OpalBase.Transaction.Output.Unspent,
                privateKey: Data,
                compressedPublicKey: Data,
                participantInput: OpalFusion.Host.ParticipantInput
            ) {
                self.unspentOutput = unspentOutput
                self.privateKey = Data(privateKey)
                self.compressedPublicKey = Data(compressedPublicKey)
                self.participantInput = participantInput
            }
        }

        enum OutputStrategy: Sendable {
            case explicit([OpalFusion.Host.ParticipantOutput])
            case valuePreserving
        }

        private static let valuePreservingOutputCount = 1
        static let minimumP2PKHOutputAmountSatoshis: UInt64 = 10_000

        let addressBook: OpalBase.Address.Book
        let reservedInputs: [ReservedInput]
        let reservedReceivingEntries: [OpalBase.Address.Book.Entry]
        let outputStrategy: OutputStrategy
        let roundReservations: CashFusionRoundReservationRegistry

        init(
            addressBook: OpalBase.Address.Book,
            reservedInputs: [ReservedInput],
            reservedReceivingEntries: [OpalBase.Address.Book.Entry],
            outputStrategy: OutputStrategy,
            roundReservations: CashFusionRoundReservationRegistry = CashFusionRoundReservationRegistry()
        ) {
            self.addressBook = addressBook
            self.reservedInputs = reservedInputs
            self.reservedReceivingEntries = reservedReceivingEntries
            self.outputStrategy = outputStrategy
            self.roundReservations = roundReservations
        }

        var selectedInputs: [OpalBase.Transaction.Output.Unspent] {
            reservedInputs.map(\.unspentOutput)
        }

        var participantInputs: [OpalFusion.Host.ParticipantInput] {
            reservedInputs.map(\.participantInput)
        }

        func participantReservation(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            if let existing = await roundReservations.roundReservation(for: roundIdentifier) {
                return existing.participantReservation
            }

            switch outputStrategy {
            case .explicit(let participantOutputs):
                let roundReservation = makeRoundReservation(
                    for: roundIdentifier,
                    reservedReceivingEntries: reservedReceivingEntries,
                    participantOutputs: participantOutputs
                )
                let stored = await roundReservations.insert(roundReservation)
                return stored.roundReservation.participantReservation
            case .valuePreserving:
                throw CashFusionRoundReservationError.dynamicReservationRequiresContext(roundIdentifier)
            }
        }

        func participantReservation(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            if let existing = await roundReservations.roundReservation(for: context.roundIdentifier) {
                return existing.participantReservation
            }

            let roundReservation = try await makeRoundReservation(for: context)
            let stored = await roundReservations.insert(roundReservation)
            if stored.inserted == false {
                try? await releaseReceivingEntries(
                    roundReservation.reservedReceivingEntries,
                    shouldKeepUsed: false
                )
            }
            return stored.roundReservation.participantReservation
        }

        func roundReservation(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> CashFusionRoundReservation {
            guard let roundReservation = await roundReservations.roundReservation(for: roundIdentifier) else {
                throw CashFusionRoundReservationError.missingRoundReservation(roundIdentifier)
            }
            return roundReservation
        }

        func complete() async throws {
            try await releaseReservations(inputOutcome: .spent, shouldKeepUsed: true)
        }

        func cancel() async throws {
            do {
                try await releaseReservations(inputOutcome: .released, shouldKeepUsed: false)
            } catch {
                await roundReservations.clearCompletedLocalOutputs()
                throw error
            }

            await roundReservations.clearCompletedLocalOutputs()
        }

        func recordCompletedLocalOutputs(
            for roundIdentifier: OpalFusion.Round.Identifier,
            finalizedTransaction: OpalBase.Transaction,
            finalizedTransactionHash: OpalBase.Transaction.Hash
        ) async throws {
            let roundReservation = try await roundReservation(for: roundIdentifier)
            let completedLocalOutputs = try makeCompletedLocalOutputs(
                finalizedTransaction: finalizedTransaction,
                finalizedTransactionHash: finalizedTransactionHash,
                participantOutputs: roundReservation.participantOutputs
            )
            await roundReservations.recordCompletedLocalOutputs(
                completedLocalOutputs,
                for: roundIdentifier
            )
        }

        func completedLocalOutputs(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async -> [OpalBase.Transaction.Output.Unspent] {
            await roundReservations.completedLocalOutputs(for: roundIdentifier)
        }

        private func releaseReservations(
            inputOutcome: InputOutcome,
            shouldKeepUsed: Bool
        ) async throws {
            let storedRoundReservations = await roundReservations.drainRoundReservations()

            switch inputOutcome {
            case .spent:
                for selectedInput in selectedInputs {
                    await addressBook.removeUTXO(selectedInput)
                }
            case .released:
                await addressBook.releaseUTXOs(Set(selectedInputs))
            }

            let receivingEntries = reservedReceivingEntries + storedRoundReservations.flatMap(\.reservedReceivingEntries)
            try await releaseReceivingEntries(receivingEntries, shouldKeepUsed: shouldKeepUsed)
        }

        private func makeCompletedLocalOutputs(
            finalizedTransaction: OpalBase.Transaction,
            finalizedTransactionHash: OpalBase.Transaction.Hash,
            participantOutputs: [OpalFusion.Host.ParticipantOutput]
        ) throws -> [OpalBase.Transaction.Output.Unspent] {
            var usedOutputIndices = Set<Int>()
            var completedLocalOutputs: [OpalBase.Transaction.Output.Unspent] = []
            completedLocalOutputs.reserveCapacity(participantOutputs.count)

            for participantOutput in participantOutputs {
                let participantLockingScript = Data(participantOutput.lockingScriptBytes)
                guard let matchingOutput = finalizedTransaction.outputs.enumerated().first(where: {
                    let outputIndex = $0.offset
                    let output = $0.element
                    return usedOutputIndices.contains(outputIndex) == false &&
                        output.tokenData == nil &&
                        output.value == participantOutput.amountSatoshis &&
                        output.lockingScript == participantLockingScript
                }) else {
                    throw CashFusionRoundReservationError.localOutputMismatch
                }

                usedOutputIndices.insert(matchingOutput.offset)
                completedLocalOutputs.append(
                    OpalBase.Transaction.Output.Unspent(
                        output: matchingOutput.element,
                        previousTransactionHash: finalizedTransactionHash,
                        previousTransactionOutputIndex: UInt32(matchingOutput.offset)
                    )
                )
            }

            return completedLocalOutputs
        }

        private func makeRoundReservation(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) async throws -> CashFusionRoundReservation {
            switch outputStrategy {
            case .explicit(let participantOutputs):
                try validateComponentLimit(
                    outputCount: participantOutputs.count,
                    context: context
                )
                return makeRoundReservation(
                    for: context.roundIdentifier,
                    reservedReceivingEntries: reservedReceivingEntries,
                    participantOutputs: participantOutputs
                )
            case .valuePreserving:
                return try await makeValuePreservingRoundReservation(for: context)
            }
        }

        private func makeRoundReservation(
            for roundIdentifier: OpalFusion.Round.Identifier,
            reservedReceivingEntries: [OpalBase.Address.Book.Entry],
            participantOutputs: [OpalFusion.Host.ParticipantOutput]
        ) -> CashFusionRoundReservation {
            .init(
                roundIdentifier: roundIdentifier,
                reservedReceivingEntries: reservedReceivingEntries,
                participantOutputs: participantOutputs,
                participantReservation: .init(
                    inputs: participantInputs,
                    outputs: participantOutputs
                )
            )
        }

        private func makeValuePreservingRoundReservation(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) async throws -> CashFusionRoundReservation {
            try validateComponentLimit(
                outputCount: Self.valuePreservingOutputCount,
                context: context
            )

            let reservedReceivingEntries: [OpalBase.Address.Book.Entry]
            do {
                reservedReceivingEntries = try await reserveReceivingEntries(
                    count: Self.valuePreservingOutputCount
                )
            } catch {
                throw _OpalBase.Account.Error.cashFusionOutputReservationFailed(error)
            }

            do {
                let participantOutputs = try makeValuePreservingParticipantOutputs(
                    reservedReceivingEntries: reservedReceivingEntries,
                    context: context
                )
                return makeRoundReservation(
                    for: context.roundIdentifier,
                    reservedReceivingEntries: reservedReceivingEntries,
                    participantOutputs: participantOutputs
                )
            } catch {
                try await releaseReceivingEntries(
                    reservedReceivingEntries,
                    shouldKeepUsed: false
                )
                throw error
            }
        }

        private func makeValuePreservingParticipantOutputs(
            reservedReceivingEntries: [OpalBase.Address.Book.Entry],
            context: OpalFusion.Host.ParticipantReservationContext
        ) throws -> [OpalFusion.Host.ParticipantOutput] {
            guard let receivingEntry = reservedReceivingEntries.first else {
                throw CashFusionRoundReservationError.componentCountLimitExceeded(
                    required: reservedInputs.count + Self.valuePreservingOutputCount,
                    limit: context.numberOfComponents
                )
            }

            let lockingScriptBytes = [UInt8](receivingEntry.address.lockingScript.data)
            let selectedInputTotal = try checkedSum(participantInputs.map(\.amountSatoshis))
            let inputFees = try checkedSum(
                reservedInputs.map {
                    try componentFee(
                        sizeBytes: 108 + $0.compressedPublicKey.count,
                        feeRateSatoshisPerKb: context.componentFeeRateSatoshisPerKb
                    )
                }
            )
            let outputFee = try componentFee(
                sizeBytes: 9 + lockingScriptBytes.count,
                feeRateSatoshisPerKb: context.componentFeeRateSatoshisPerKb
            )
            let targetExcessFee = try targetExcessFee(for: context)
            let requiredValue = try checkedSum([inputFees, outputFee, targetExcessFee])

            guard selectedInputTotal >= requiredValue else {
                throw CashFusionRoundReservationError.insufficientSelectedInputValue(
                    required: requiredValue,
                    available: selectedInputTotal
                )
            }

            let outputAmount = selectedInputTotal - requiredValue
            guard outputAmount >= Self.minimumP2PKHOutputAmountSatoshis else {
                throw CashFusionRoundReservationError.outputAmountBelowMinimum(
                    minimum: Self.minimumP2PKHOutputAmountSatoshis,
                    actual: outputAmount
                )
            }

            return [
                .init(
                    lockingScriptBytes: lockingScriptBytes,
                    amountSatoshis: outputAmount
                )
            ]
        }

        private func validateComponentLimit(
            outputCount: Int,
            context: OpalFusion.Host.ParticipantReservationContext
        ) throws {
            let required = reservedInputs.count + outputCount
            guard required <= Int(context.numberOfComponents) else {
                throw CashFusionRoundReservationError.componentCountLimitExceeded(
                    required: required,
                    limit: context.numberOfComponents
                )
            }
        }

        private func reserveReceivingEntries(
            count: Int
        ) async throws -> [OpalBase.Address.Book.Entry] {
            var reservedEntries: [OpalBase.Address.Book.Entry] = []
            reservedEntries.reserveCapacity(count)

            do {
                for _ in 0..<count {
                    let reservedEntry = try await addressBook.reserveNextEntry(for: .receiving)
                    reservedEntries.append(reservedEntry)
                }
            } catch {
                try await releaseReceivingEntries(
                    reservedEntries,
                    shouldKeepUsed: false
                )
                throw error
            }

            return reservedEntries
        }

        private func releaseReceivingEntries(
            _ entries: [OpalBase.Address.Book.Entry],
            shouldKeepUsed: Bool
        ) async throws {
            var firstError: Swift.Error?
            var releasedAddresses = Set<OpalBase.Address>()

            for entry in entries where releasedAddresses.insert(entry.address).inserted {
                do {
                    _ = try await addressBook.releaseReservation(
                        address: entry.address,
                        shouldKeepUsed: shouldKeepUsed
                    )
                } catch {
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            if let firstError {
                throw firstError
            }
        }

        private func targetExcessFee(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) throws -> UInt64 {
            guard context.minimumExcessFeeSatoshis <= context.maximumExcessFeeSatoshis else {
                throw CashFusionRoundReservationError.invalidExcessFeeRange(
                    minimum: context.minimumExcessFeeSatoshis,
                    maximum: context.maximumExcessFeeSatoshis
                )
            }

            return context.minimumExcessFeeSatoshis +
                ((context.maximumExcessFeeSatoshis - context.minimumExcessFeeSatoshis) / 2)
        }

        private func componentFee(
            sizeBytes: Int,
            feeRateSatoshisPerKb: UInt64
        ) throws -> UInt64 {
            guard sizeBytes >= 0 else {
                throw CashFusionRoundReservationError.amountOverflow
            }

            let product = UInt64(sizeBytes)
                .multipliedReportingOverflow(by: feeRateSatoshisPerKb)
            guard product.overflow == false else {
                throw CashFusionRoundReservationError.amountOverflow
            }

            let rounded = product.partialValue.addingReportingOverflow(999)
            guard rounded.overflow == false else {
                throw CashFusionRoundReservationError.amountOverflow
            }

            return rounded.partialValue / 1_000
        }

        private func checkedSum(_ values: [UInt64]) throws -> UInt64 {
            try values.reduce(UInt64(0)) { partialResult, value in
                let sum = partialResult.addingReportingOverflow(value)
                guard sum.overflow == false else {
                    throw CashFusionRoundReservationError.amountOverflow
                }
                return sum.partialValue
            }
        }

        private enum InputOutcome {
            case spent
            case released
        }
    }
}
#endif
