// OpalBase+Address+Book~Mosaic.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Address.Book {
    /// Atomically acquires exact inputs under one Mosaic owner, excluding other reservations.
    func acquireMosaicInputs(
        _ inputs: [OpalBase.Transaction.Output.Unspent],
        ownedBy reference: OpalFusion.Host.MosaicReservationReference
    ) throws {
        let selected = Set(inputs)
        try utxoStore.reserve(selected, tokenSelectionPolicy: .excludeTokenUTXOs)
        // Transfer immediately without suspension; ordinary release/refresh cannot
        // clear the owner-scoped hold while signing or recovery is uncertain.
        utxoStore.quarantineMosaicOutpoints(
            Set(inputs.map(UTXORepository.Outpoint.init)),
            ownerIdentifier: reference.identifier,
            ownerGeneration: reference.generation
        )
        utxoStore.release(selected)
    }

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
        !Set(utxoStore.reservedUTXOs.map(UTXORepository.Outpoint.init))
            .isDisjoint(with: Set(inputs.map(UTXORepository.Outpoint.init)))
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
        ownedBy reference: OpalFusion.Host.MosaicReservationReference? = nil,
        maintainingGapWith maintainGap: (@Sendable () async throws -> Void)? = nil
    ) async throws -> Entry {
        guard let currentEntry = findEntry(for: plannedEntry.address),
              currentEntry.derivationPath == plannedEntry.derivationPath,
              currentEntry.derivationPath.usage == .receiving,
              !currentEntry.isUsed,
              !currentEntry.isReserved else {
            throw Error.entryNotFound
        }
        let reservedEntry: Entry
        if let reference {
            reservedEntry = try inventory.reserveMosaicEntry(
                address: plannedEntry.address,
                ownedBy: .init(identifier: reference.identifier, generation: reference.generation)
            )
        } else {
            reservedEntry = try reserveEntry(address: plannedEntry.address)
        }
        do {
            if let maintainGap {
                try await maintainGap()
            } else {
                try await generateEntriesIfNeeded(for: .receiving)
            }
            return reservedEntry
        } catch {
            if let reference {
                _ = try? retireMosaicReceivingEntry(reservedEntry, ownedBy: reference)
            } else {
                _ = try? releaseReservation(address: reservedEntry.address, shouldKeepUsed: true)
            }
            throw error
        }
    }

    /// Retires a planned output only if unreserved or held by this exact attempt.
    @discardableResult
    func retireMosaicReceivingEntry(
        _ entry: Entry,
        ownedBy reference: OpalFusion.Host.MosaicReservationReference
    ) throws -> Entry {
        guard let current = findEntry(for: entry.address),
              current.derivationPath == entry.derivationPath,
              current.derivationPath.usage == .receiving else {
            throw Error.entryNotFound
        }
        return try inventory.retireMosaicEntry(
            address: entry.address,
            ownedBy: .init(identifier: reference.identifier, generation: reference.generation)
        )
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
