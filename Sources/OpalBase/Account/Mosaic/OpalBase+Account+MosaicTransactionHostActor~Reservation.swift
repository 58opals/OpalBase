// OpalBase+Account+MosaicTransactionHostActor~Reservation.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account.MosaicTransactionHostActor {
    func reserveMosaicContribution(
        for request: OpalFusion.Host.MosaicReservationRequest
    ) async throws -> OpalFusion.Host.MosaicReservationLease {
        if let existingRequest = reservationRequest {
            guard existingRequest == request else {
                throw OpalBase.Account.MosaicHostFailure.inPlaceRetryNotPermitted
            }
            guard !releaseStarted, !commitStarted, !isReleased,
                  let reservationLease else {
                throw OpalBase.Account.MosaicHostFailure.terminalReservation
            }
            return reservationLease
        }

        guard request.networkGenesisHash == expectedNetworkGenesisHash else {
            throw OpalBase.Account.MosaicHostFailure.invalidNetworkBinding
        }
        guard request.expiresAt > currentDate() else {
            throw OpalBase.Account.MosaicHostFailure.reservationExpired
        }
        guard selectedInputs.count + outputAmountsSatoshis.count <= request.componentCount else {
            throw OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
        }

        reservationRequest = request
        let inputEntries: [OpalBase.Address.Book.Entry]
        do {
            inputEntries = try await validateSelectedInputs()
            try await addressBook.reserveUTXOs(
                Set(selectedInputs),
                tokenSelectionPolicy: .excludeTokenUTXOs
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw OpalBase.Account.MosaicHostFailure.reservationUnavailable
        }

        var receivingEntries: [OpalBase.Address.Book.Entry] = []
        do {
            receivingEntries.reserveCapacity(outputAmountsSatoshis.count)
            for _ in outputAmountsSatoshis {
                receivingEntries.append(
                    try await reserveReceivingEntry(addressBook)
                )
            }

            let inputRecords = try await makeReservedInputRecords(entries: inputEntries)
            let participantOutputs = zip(receivingEntries, outputAmountsSatoshis).map {
                entry, amountSatoshis in
                OpalFusion.Host.ParticipantOutput(
                    lockingScriptBytes: [UInt8](entry.address.lockingScript.data),
                    amountSatoshis: amountSatoshis
                )
            }
            let reference = OpalFusion.Host.MosaicReservationReference(
                identifier: makeReservationIdentifier(),
                generation: generation
            )
            let lease = try OpalFusion.Host.MosaicReservationLease(
                reference: reference,
                expiresAt: request.expiresAt,
                participantReservation: .init(
                    inputs: inputRecords.map(\.participantInput),
                    outputs: participantOutputs
                )
            )

            guard request.expiresAt > currentDate() else {
                throw OpalBase.Account.MosaicHostFailure.reservationExpired
            }
            reservedInputs = inputRecords
            reservedReceivingEntries = receivingEntries
            reservationLease = lease
            scheduleExpiration(for: lease)
            return lease
        } catch {
            await addressBook.releaseUTXOs(Set(selectedInputs))
            do {
                try await retireReceivingEntries(receivingEntries)
            } catch {
                throw OpalBase.Account.MosaicHostFailure.reservationCleanupFailed
            }
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
                try await expireMosaicReservation(
                    lease.reference,
                    at: lease.expiresAt
                )
            } catch {
                return
            }
        }
    }
}
#endif
