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

    /// Reads wallet reservation state without treating Mosaic quarantine as a reservation effect.
    func hasReservedMosaicInputs(
        _ inputs: [OpalBase.Transaction.Output.Unspent]
    ) -> Bool {
        !utxoStore.reservedUTXOs.isDisjoint(with: Set(inputs))
    }

    /// Selects exact unused receiving identities without reserving them.
    func prepareMosaicReceivingEntries(
        count: Int
    ) async throws -> [Entry] {
        guard count > 0 else { return [] }
        try await generateEntriesIfNeeded(for: .receiving)
        var candidates = listEntries(for: .receiving).filter {
            !$0.isUsed && !$0.isReserved
        }
        if candidates.count < count {
            try await generateEntries(
                for: .receiving,
                entryCount: count - candidates.count,
                isUsed: false
            )
            candidates = listEntries(for: .receiving).filter {
                !$0.isUsed && !$0.isReserved
            }
        }
        guard candidates.count >= count else { throw Error.entryNotFound }
        return Array(candidates.prefix(count))
    }

    /// Reserves only one exact previously planned receiving identity.
    func reserveMosaicReceivingEntry(
        _ plannedEntry: Entry,
        maintainingGapWith maintainGap: (@Sendable () async throws -> Void)? = nil
    ) async throws -> Entry {
        guard let currentEntry = findEntry(for: plannedEntry.address),
              currentEntry.derivationPath == plannedEntry.derivationPath,
              currentEntry.derivationPath.usage == .receiving,
              !currentEntry.isUsed,
              !currentEntry.isReserved else {
            throw Error.entryNotFound
        }
        let reservedEntry = try reserveEntry(address: plannedEntry.address)
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

    /// Convenience for non-recovery callers that do not need a pre-effect plan.
    func reserveMosaicReceivingEntry(
        maintainingGapWith maintainGap: (@Sendable () async throws -> Void)? = nil
    ) async throws -> Entry {
        guard let planned = try await prepareMosaicReceivingEntries(count: 1)
            .first else {
            throw Error.entryNotFound
        }
        return try await reserveMosaicReceivingEntry(
            planned,
            maintainingGapWith: maintainGap
        )
    }
}
#endif
