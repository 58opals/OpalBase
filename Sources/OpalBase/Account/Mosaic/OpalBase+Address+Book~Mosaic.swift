// OpalBase+Address+Book~Mosaic.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Address.Book {
    /// Quarantines journal-authenticated selected inputs by outpoint identity.
    ///
    /// Every selected input must have a structurally valid transaction hash.
    func quarantineMosaicInputs(
        _ selectedInputs: [OpalBase.Account.MosaicAttemptJournal.SelectedInput],
        ownedBy reservationReference: OpalFusion.Host.MosaicReservationReference
    ) {
        let outpoints = Set(selectedInputs.map { selectedInput in
            UTXORepository.Outpoint(
                transactionHash: .init(
                    naturalOrder: selectedInput.transactionHash
                ),
                outputIndex: selectedInput.outputIndex
            )
        })
        quarantineMosaicOutpoints(
            outpoints,
            ownerIdentifier: reservationReference.identifier,
            ownerGeneration: reservationReference.generation
        )
    }

    /// Releases only the quarantine owned by the exact reservation reference.
    func releaseMosaicInputQuarantine(
        ownedBy reservationReference: OpalFusion.Host.MosaicReservationReference
    ) {
        releaseMosaicOutpointQuarantine(
            ownerIdentifier: reservationReference.identifier,
            ownerGeneration: reservationReference.generation
        )
    }

    func reserveMosaicReceivingEntry(
        maintainingGapWith maintainGap: (@Sendable () async throws -> Void)? = nil
    ) async throws -> Entry {
        let candidateEntry = try await selectNextEntry(for: .receiving)
        let reservedEntry = try reserveEntry(address: candidateEntry.address)
        do {
            if let maintainGap {
                try await maintainGap()
            } else {
                try await generateEntriesIfNeeded(for: .receiving)
            }
            return reservedEntry
        } catch {
            _ = try? releaseReservation(
                address: reservedEntry.address,
                shouldKeepUsed: true
            )
            throw error
        }
    }
}
#endif
