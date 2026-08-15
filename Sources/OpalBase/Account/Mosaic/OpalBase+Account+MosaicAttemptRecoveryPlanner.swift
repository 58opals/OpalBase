// OpalBase+Account+MosaicAttemptRecoveryPlanner.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    enum MosaicAttemptRecoveryPlanner {
        static func plan(
            for records: [MosaicAttemptJournal.Record]
        ) throws -> Plan {
            guard let first = records.first else { return .noAction }
            guard case let .attemptBinding(binding) = first else {
                throw Error.invalidFirstRecord
            }
            try validate(binding)

            var state = State.attemptBound(binding)
            var previous = first
            var reservationRequest:
                OpalFusion.Host.MosaicReservationRequest?
            var selectedInputs: [MosaicAttemptJournal.SelectedInput]?
            var outputAmountsSatoshis: [UInt64]?
            for record in records.dropFirst() {
                guard record != previous else {
                    throw Error.invalidTransition
                }
                guard record.reference
                        == binding.walletReservationReference else {
                    throw Error.reservationReferenceMismatch
                }
                if case let .reservationIntent(
                    reference,
                    request,
                    inputs,
                    amounts
                ) = record {
                    guard reservationRequest == nil,
                          Data(request.attemptIdentifier)
                            == binding.attemptIdentifier,
                          reference == binding.walletReservationReference else {
                        throw Error.attemptBindingMismatch
                    }
                    try validateReservationIntent(
                        reference: reference,
                        request: request,
                        selectedInputs: inputs,
                        outputAmountsSatoshis: amounts
                    )
                    reservationRequest = request
                    selectedInputs = inputs
                    outputAmountsSatoshis = amounts
                } else if case let .reservationPrepared(
                    request,
                    inputs,
                    amounts,
                    lease
                ) = record {
                    guard reservationRequest == nil,
                          Data(request.attemptIdentifier)
                            == binding.attemptIdentifier,
                          lease.reference
                            == binding.walletReservationReference else {
                        throw Error.attemptBindingMismatch
                    }
                    try validateReservationIntent(
                        reference: lease.reference,
                        request: request,
                        selectedInputs: inputs,
                        outputAmountsSatoshis: amounts
                    )
                    try validateLease(
                        lease,
                        reservationRequest: request,
                        selectedInputs: inputs,
                        outputAmountsSatoshis: amounts
                    )
                    reservationRequest = request
                    selectedInputs = inputs
                    outputAmountsSatoshis = amounts
                } else {
                    try validate(
                        record,
                        reservationRequest: reservationRequest,
                        selectedInputs: selectedInputs,
                        outputAmountsSatoshis: outputAmountsSatoshis
                    )
                }
                state = try state.applying(record)
                previous = record
            }
            return state.plan
        }

        static func binding(
            for records: [MosaicAttemptJournal.Record]
        ) throws -> MosaicAttemptBinding? {
            guard let first = records.first else { return nil }
            guard case let .attemptBinding(binding) = first else {
                throw Error.attemptBindingMismatch
            }
            try validate(binding)
            return binding
        }

        static func requirePrivateAlphaProfile(
            for records: [MosaicAttemptJournal.Record]
        ) throws {
            for record in records {
                let request: OpalFusion.Host.MosaicReservationRequest
                switch record {
                case let .reservationIntent(_, value, _, _),
                     let .reservationPrepared(value, _, _, _):
                    request = value
                default:
                    continue
                }
                guard request.networkGenesisHash
                        == OpalFusion.Mosaic.Profile.opalMainnetAlpha
                            .networkGenesisHash,
                      request.transactionProfileIdentifier
                        == OpalFusion.Mosaic.Profile.opalMainnetAlpha
                            .transactionProfileIdentifier else {
                    throw Error.unsupportedPrivateAlphaProfile
                }
                return
            }
        }

        private static func validate(
            _ binding: MosaicAttemptBinding
        ) throws {
            guard binding.attemptIdentifier.count == 32,
                  binding.generationIdentifier.count == 32,
                  binding.materialIdentifier.count == 32 else {
                throw Error.attemptBindingMismatch
            }
        }

        private static func validateReservationIntent(
            reference: OpalFusion.Host.MosaicReservationReference,
            request: OpalFusion.Host.MosaicReservationRequest,
            selectedInputs: [MosaicAttemptJournal.SelectedInput],
            outputAmountsSatoshis: [UInt64]
        ) throws {
            guard let profile = supportedProfile(for: request) else {
                throw Error.attemptBindingMismatch
            }
            guard !request.attemptIdentifier.isEmpty,
                  request.expiresAt.timeIntervalSince1970.isFinite,
                  !selectedInputs.isEmpty,
                  !outputAmountsSatoshis.isEmpty,
                  outputAmountsSatoshis.allSatisfy({ $0 > 0 }),
                  sum(outputAmountsSatoshis) != nil,
                  selectedInputs.count + outputAmountsSatoshis.count
                    <= request.componentCount,
                  request.componentCount
                    == profile.rosterPolicy.componentCountPerContributor,
                  let contributionPolicy = MosaicProfileContributionPolicy(
                    profile: profile
                  ),
                  contributionPolicy.accepts(
                    feeRateSatoshisPerByte:
                        request.feeRateSatoshisPerByte,
                    minimumExcessFeeSatoshis:
                        request.minimumExcessFeeSatoshis,
                    maximumExcessFeeSatoshis:
                        request.maximumExcessFeeSatoshis,
                    requiredExcessFeeSatoshis:
                        request.requiredExcessFeeSatoshis
                  ),
                  contributionPolicy.matchesLocalContribution(
                    inputAmountsSatoshis: selectedInputs.map(
                        \.amountSatoshis
                    ),
                    outputAmountsSatoshis: outputAmountsSatoshis,
                    requiredExcessFeeSatoshis:
                        request.requiredExcessFeeSatoshis
                  ) else {
                throw Error.invalidRecord
            }

            for (index, input) in selectedInputs.enumerated() {
                guard input.transactionHash.count
                        == OpalBase.Transaction.Hash.expectedByteCount,
                      input.amountSatoshis > 0,
                      !input.lockingScript.isEmpty,
                      !selectedInputs[..<index].contains(where: {
                        $0.transactionHash == input.transactionHash
                            && $0.outputIndex == input.outputIndex
                      }) else {
                    throw Error.invalidRecord
                }
            }
            guard sum(selectedInputs.map(\.amountSatoshis)) != nil else {
                throw Error.invalidRecord
            }
        }

        private static func validate(
            _ record: MosaicAttemptJournal.Record,
            reservationRequest: OpalFusion.Host.MosaicReservationRequest?,
            selectedInputs: [MosaicAttemptJournal.SelectedInput]?,
            outputAmountsSatoshis: [UInt64]?
        ) throws {
            switch record {
            case .attemptBinding, .reservationIntent, .reservationPrepared:
                throw Error.invalidTransition
            case let .reserved(lease):
                guard let reservationRequest,
                      let selectedInputs,
                      let outputAmountsSatoshis else {
                    throw Error.invalidRecord
                }
                try validateLease(
                    lease,
                    reservationRequest: reservationRequest,
                    selectedInputs: selectedInputs,
                    outputAmountsSatoshis: outputAmountsSatoshis
                )
            case let .signingIntent(request):
                guard let reservationRequest,
                      request.roundIdentifier
                        == reservationRequest.roundIdentifier,
                      request.feeRateSatoshisPerByte
                        == reservationRequest.feeRateSatoshisPerByte,
                      request.minimumExcessFeeSatoshis
                        == reservationRequest.minimumExcessFeeSatoshis,
                      request.maximumExcessFeeSatoshis
                        == reservationRequest.maximumExcessFeeSatoshis,
                      request.requiredExcessFeeSatoshis
                        == reservationRequest.requiredExcessFeeSatoshis,
                      request.transactionProfileIdentifier
                        == reservationRequest.transactionProfileIdentifier else {
                    throw Error.attemptBindingMismatch
                }
            case let .locallySigned(_, transaction):
                let complete = try OpalFusion.Host.MosaicCompleteTransaction(
                    transactionBytes: transaction.signedFusionTransactionBytes
                )
                _ = try MosaicExactTransaction(complete)
            case .releaseIntent, .released:
                break
            case let .commitIntent(_, transaction),
                 let .committed(_, transaction),
                 let .broadcastApproved(_, transaction),
                 let .broadcastIntent(_, transaction):
                _ = try MosaicExactTransaction(transaction)
            case let .broadcastAccepted(_, transaction, transactionHash):
                guard try MosaicExactTransaction(transaction).hash
                        == transactionHash else {
                    throw Error.transactionHashMismatch
                }
            case let .chainObservation(_, transaction, observation):
                guard try MosaicExactTransaction(transaction).hash
                        == observation.transactionHash else {
                    throw Error.transactionHashMismatch
                }
            case let .terminalDisposition(_, transaction, disposition):
                switch disposition {
                case .walletReleased:
                    guard transaction == nil else {
                        throw Error.invalidRecord
                    }
                case let .chainFinalized(
                    transactionHash,
                    blockHash,
                    confirmations
                ):
                    guard let transaction,
                          try MosaicExactTransaction(transaction).hash
                            == transactionHash,
                          blockHash.count
                            == OpalBase.Transaction.Hash.expectedByteCount,
                          confirmations > 0 else {
                        throw Error.transactionHashMismatch
                    }
                }
            }
        }

        private static func sum(_ values: [UInt64]) -> UInt64? {
            var total: UInt64 = 0
            for value in values {
                let result = total.addingReportingOverflow(value)
                guard !result.overflow else { return nil }
                total = result.partialValue
            }
            return total
        }

        private static func supportedProfile(
            for request: OpalFusion.Host.MosaicReservationRequest
        ) -> OpalFusion.Mosaic.Profile? {
            [
                OpalFusion.Mosaic.Profile.opalV0,
                .opalMainnetAlpha,
            ].first {
                $0.networkGenesisHash == request.networkGenesisHash
                    && $0.transactionProfileIdentifier
                        == request.transactionProfileIdentifier
            }
        }

        private static func validateLease(
            _ lease: OpalFusion.Host.MosaicReservationLease,
            reservationRequest: OpalFusion.Host.MosaicReservationRequest,
            selectedInputs: [MosaicAttemptJournal.SelectedInput],
            outputAmountsSatoshis: [UInt64]
        ) throws {
            guard lease.expiresAt == reservationRequest.expiresAt,
                  lease.participantReservation.inputs.count
                    == selectedInputs.count,
                  lease.participantReservation.outputs.count
                    == outputAmountsSatoshis.count else {
                throw Error.invalidRecord
            }
            for (selectedInput, participantInput) in zip(
                selectedInputs,
                lease.participantReservation.inputs
            ) {
                let lockingScript = Data(participantInput.lockingScriptBytes)
                guard Data(participantInput.outpointTransactionHashBytes)
                        == selectedInput.transactionHash.reversedData,
                      participantInput.outpointIndex == selectedInput.outputIndex,
                      participantInput.amountSatoshis
                        == selectedInput.amountSatoshis,
                      lockingScript == selectedInput.lockingScript,
                      let publicKeyBytes = participantInput.publicKey,
                      let publicKey = try? OpalBase.Key.PublicKey(
                        compressedData: Data(publicKeyBytes)
                      ),
                      let script = try? OpalBase.Script.decode(
                        lockingScript: lockingScript
                      ),
                      case let .p2pkh_OPCHECKSIG(expectedHash) = script,
                      OpalBase.Key.PublicKey.Hash(publicKey: publicKey)
                        == expectedHash else {
                    throw Error.invalidRecord
                }
            }

            let outputs = lease.participantReservation.outputs
            let outputScripts = outputs.map {
                Data($0.lockingScriptBytes)
            }
            guard outputs.map(\.amountSatoshis) == outputAmountsSatoshis,
                  outputScripts.allSatisfy({ !$0.isEmpty }),
                  Set(outputScripts).count == outputScripts.count else {
                throw Error.invalidRecord
            }
        }
    }
}

private extension _OpalBase.Account.MosaicAttemptJournal.Record {
    var reference: OpalFusion.Host.MosaicReservationReference {
        switch self {
        case let .attemptBinding(binding):
            binding.walletReservationReference
        case let .reservationIntent(reference, _, _, _),
             let .locallySigned(reference, _),
             let .releaseIntent(reference),
             let .released(reference),
             let .commitIntent(reference, _),
             let .committed(reference, _),
             let .broadcastApproved(reference, _),
             let .broadcastIntent(reference, _),
             let .broadcastAccepted(reference, _, _),
             let .chainObservation(reference, _, _),
             let .terminalDisposition(reference, _, _):
            reference
        case let .reservationPrepared(_, _, _, lease), let .reserved(lease):
            lease.reference
        case let .signingIntent(request):
            request.reservationReference
        }
    }
}
#endif
