// OpalBase+Account+MosaicTransactionHostActor~Reservation.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account.MosaicTransactionHostActor {
    func reserveMosaicContribution(
        for request: OpalFusion.Host.MosaicReservationRequest
    ) async throws -> OpalFusion.Host.MosaicReservationLease {
        switch lifecycle {
        case .idle:
            break
        case .reservationPrepared, .reserved, .finalizationPending, .validating,
             .signingIntent, .localSignaturePending, .localSignaturePersisting,
             .locallySigned, .commitPending, .commitIntentPersisting,
             .commitRecovery, .committing, .committed, .releaseIntent, .released:
            guard let existingRequest = reservationRequest else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            guard existingRequest == request else {
                throw OpalBase.Account.MosaicHostFailure.inPlaceRetryNotPermitted
            }
            guard let reservationLease else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            switch lifecycle {
            case .commitPending, .commitIntentPersisting, .commitRecovery,
                 .committing, .committed, .releaseIntent, .released:
                throw OpalBase.Account.MosaicHostFailure.terminalReservation
            case .idle, .reservationPrepared, .reserved, .finalizationPending,
                 .validating, .signingIntent, .localSignaturePending,
                .localSignaturePersisting, .locallySigned:
                return reservationLease
            }
        }

        guard request.networkGenesisHash == expectedNetworkGenesisHash else {
            throw OpalBase.Account.MosaicHostFailure.invalidNetworkBinding
        }
        guard request.expiresAt > currentDate() else {
            throw OpalBase.Account.MosaicHostFailure.reservationExpired
        }
        guard profile.networkGenesisHash == expectedNetworkGenesisHash,
              request.transactionProfileIdentifier == profile.transactionProfileIdentifier,
              request.componentCount == profile.rosterPolicy.componentCountPerContributor,
              contributionPolicy.accepts(
                feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis: request.minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: request.maximumExcessFeeSatoshis,
                requiredExcessFeeSatoshis: request.requiredExcessFeeSatoshis
              ) else {
            throw OpalBase.Account.MosaicHostFailure.invalidReservationProfile
        }
        guard selectedInputs.count + outputAmountsSatoshis.count <= request.componentCount else {
            throw OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
        }
        guard contributionPolicy.matchesLocalContribution(
            inputAmountsSatoshis: selectedInputs.map(\.value),
            outputAmountsSatoshis: outputAmountsSatoshis,
            requiredExcessFeeSatoshis: request.requiredExcessFeeSatoshis
        ) else {
            throw OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
        }
        guard Data(request.attemptIdentifier)
                == attemptBinding.attemptIdentifier else {
            throw OpalBase.Account.MosaicHostFailure.invalidReservationProfile
        }

        let reference = attemptBinding.walletReservationReference
        let inputEntries: [OpalBase.Address.Book.Entry]
        let plannedReceivingEntries: [OpalBase.Address.Book.Entry]
        let inputRecords: [OpalBase.Account.MosaicReservedInputRecord]
        let lease: OpalFusion.Host.MosaicReservationLease
        do {
            inputEntries = try await validateSelectedInputs()
            plannedReceivingEntries = try await addressBook
                .prepareMosaicReceivingEntries(
                    count: outputAmountsSatoshis.count
                )
            inputRecords = try await makeReservedInputRecords(
                entries: inputEntries
            )
            let participantOutputs = zip(
                plannedReceivingEntries,
                outputAmountsSatoshis
            ).map { entry, amountSatoshis in
                OpalFusion.Host.ParticipantOutput(
                    lockingScriptBytes: [UInt8](
                        entry.address.lockingScript.data
                    ),
                    amountSatoshis: amountSatoshis
                )
            }
            lease = try OpalFusion.Host.MosaicReservationLease(
                reference: reference,
                expiresAt: request.expiresAt,
                participantReservation: .init(
                    inputs: inputRecords.map(\.participantInput),
                    outputs: participantOutputs
                )
            )
        } catch let failure as OpalBase.Account.MosaicHostFailure {
            throw failure
        } catch {
            throw OpalBase.Account.MosaicHostFailure.reservationUnavailable
        }

        reservationRequest = request
        lifecycle = .reservationPrepared
        try await persist(
            .reservationPrepared(
                request: request,
                selectedInputs: selectedInputs.map(
                    OpalBase.Account.MosaicAttemptJournal.SelectedInput.init
                ),
                outputAmountsSatoshis: outputAmountsSatoshis,
                lease: lease
            )
        )

        var didReserveInputs = false
        var receivingEntries: [OpalBase.Address.Book.Entry] = []
        do {
            try Task.checkCancellation()
            try await addressBook.reserveUTXOs(
                Set(selectedInputs),
                tokenSelectionPolicy: .excludeTokenUTXOs
            )
            didReserveInputs = true
            try Task.checkCancellation()

            receivingEntries.reserveCapacity(outputAmountsSatoshis.count)
            for plannedEntry in plannedReceivingEntries {
                receivingEntries.append(
                    try await reserveReceivingEntry(
                        addressBook,
                        plannedEntry
                    )
                )
                try Task.checkCancellation()
            }

            guard request.expiresAt > currentDate() else {
                throw OpalBase.Account.MosaicHostFailure.reservationExpired
            }
            try await persist(.reserved(lease))
            try Task.checkCancellation()
            guard request.expiresAt > currentDate() else {
                throw OpalBase.Account.MosaicHostFailure.reservationExpired
            }
            reservedInputs = inputRecords
            reservedReceivingEntries = receivingEntries
            reservationLease = lease
            lifecycle = .reserved
            scheduleExpiration(for: lease)
            return lease
        } catch {
            do {
                try await persist(.releaseIntent(reference))
            } catch {
                lifecycle = .releaseIntent
                throw error
            }
            lifecycle = .releaseIntent
            if didReserveInputs {
                await addressBook.releaseUTXOs(Set(selectedInputs))
            }
            do {
                try await retireReceivingEntries(plannedReceivingEntries)
            } catch {
                throw OpalBase.Account.MosaicHostFailure.reservationCleanupFailed
            }
            try await persist(.released(reference))
            lifecycle = .released
            if let cancellation = error as? CancellationError {
                throw cancellation
            }
            if let hostFailure = error as? OpalBase.Account.MosaicHostFailure {
                throw hostFailure
            }
            throw OpalBase.Account.MosaicHostFailure.reservationUnavailable
        }
    }

    func validateSelectedInputs() async throws -> [OpalBase.Address.Book.Entry] {
        var entries: [OpalBase.Address.Book.Entry] = []
        entries.reserveCapacity(selectedInputs.count)

        for selectedInput in selectedInputs {
            guard selectedInput.tokenData == nil else {
                throw OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
            }
            let script = try OpalBase.Script.decode(lockingScript: selectedInput.lockingScript)
            guard case .p2pkh_OPCHECKSIG = script else {
                throw OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
            }
            let address = try OpalBase.Address(script: script)
            guard let entry = await addressBook.findEntry(for: address) else {
                throw OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
            }
            entries.append(entry)
        }
        return entries
    }

    func makeReservedInputRecords(
        entries: [OpalBase.Address.Book.Entry]
    ) async throws -> [OpalBase.Account.MosaicReservedInputRecord] {
        var records: [OpalBase.Account.MosaicReservedInputRecord] = []
        records.reserveCapacity(selectedInputs.count)

        for (selectedInput, entry) in zip(selectedInputs, entries) {
            let signingKey = try await addressBook.generateSigningKey(
                at: entry.derivationPath.index,
                for: entry.derivationPath.usage
            )
            let script = try OpalBase.Script.decode(lockingScript: selectedInput.lockingScript)
            guard case .p2pkh_OPCHECKSIG(let expectedHash) = script,
                  OpalBase.Key.PublicKey.Hash(publicKey: signingKey.publicKey) == expectedHash else {
                throw OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
            }
            records.append(
                .init(
                    unspentOutput: selectedInput,
                    signingKey: signingKey,
                    participantInput: .init(
                        outpointTransactionHashBytes: [UInt8](
                            selectedInput.previousTransactionHash.reverseOrder
                        ),
                        outpointIndex: selectedInput.previousTransactionOutputIndex,
                        amountSatoshis: selectedInput.value,
                        lockingScriptBytes: [UInt8](selectedInput.lockingScript),
                        publicKey: [UInt8](signingKey.publicKey.compressedData)
                    )
                )
            )
        }
        return records
    }

    func scheduleExpiration(for lease: OpalFusion.Host.MosaicReservationLease) {
        let sleepUntilDate = sleepUntilDate
        expirationTask = Task { [self] in
            do {
                try await sleepUntilDate(lease.expiresAt)
                try Task.checkCancellation()
                try await expireScheduledMosaicReservation(
                    lease.reference,
                    at: lease.expiresAt
                )
            } catch {
                return
            }
        }
    }

    func expireScheduledMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference,
        at date: Date
    ) async throws {
        expirationTask = nil
        try await expireMosaicReservation(reservationReference, at: date)
    }
}
#endif
