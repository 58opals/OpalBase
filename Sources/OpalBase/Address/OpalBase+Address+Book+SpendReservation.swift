// OpalBase+Address+Book+SpendReservation.swift

import Foundation

extension _OpalBase.Address.Book {
    struct SpendReservation: Identifiable, Sendable {
        enum Outcome {
            case completed
            case cancelled
        }
        
        struct State: Sendable {
            let utxos: Set<OpalBase.Transaction.Output.Unspent>
            let entry: Entry
            let hasBeenUsedPreviously: Bool
            let reservedAt: Date
        }
        
        let id: UUID
        let changeEntry: Entry
        let reservationDate: Date
        
        init(id: UUID, changeEntry: Entry, reservedAt: Date) {
            self.id = id
            self.changeEntry = changeEntry
            self.reservationDate = reservedAt
        }
    }
}

extension _OpalBase.Address.Book {
    func reserveSpend(utxos: [OpalBase.Transaction.Output.Unspent],
                      changeEntry: Entry,
                      tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy) async throws -> SpendReservation {
        let utxoSet = Set(utxos)
        guard !utxoSet.isEmpty else {
            throw OpalBase.Address.Book.Error.utxoNotFound
        }
        guard utxoSet.count == utxos.count else {
            var seenUTXOs = Set<OpalBase.Transaction.Output.Unspent>()
            let duplicatedUTXO = utxos.first { !seenUTXOs.insert($0).inserted } ?? utxos[0]
            throw OpalBase.Address.Book.Error.utxoDuplicated(duplicatedUTXO)
        }
        
        if let existingReservation = findMatchingReservation(for: utxoSet) {
            guard utxoStore.containsExact(utxoSet, tokenSelectionPolicy: tokenSelectionPolicy) else {
                throw OpalBase.Address.Book.Error.utxoNotFound
            }

            let refreshedDate = Date.now
            let refreshedState = SpendReservation.State(utxos: existingReservation.state.utxos,
                                                        entry: existingReservation.state.entry,
                                                        hasBeenUsedPreviously: existingReservation.state.hasBeenUsedPreviously,
                                                        reservedAt: refreshedDate)
            spendReservationStates[existingReservation.identifier] = refreshedState
            scheduleAutomaticSpendReservationRelease(for: existingReservation.identifier)
            
            return SpendReservation(id: existingReservation.identifier,
                                    changeEntry: refreshedState.entry,
                                    reservedAt: refreshedDate)
        }
        
        let identifier = UUID()
        let reservationDate = Date.now
        
        do {
            try utxoStore.reserve(utxoSet, tokenSelectionPolicy: tokenSelectionPolicy)
        } catch {
            throw error
        }

        do {
            let changeReservation = try await reserveFreshChangeEntry(preferred: changeEntry)

            spendReservationStates[identifier] = SpendReservation.State(
                utxos: utxoSet,
                entry: changeReservation.entry,
                hasBeenUsedPreviously: changeReservation.hasBeenUsedPreviously,
                reservedAt: reservationDate
            )

            scheduleAutomaticSpendReservationRelease(for: identifier)

            return SpendReservation(
                id: identifier,
                changeEntry: changeReservation.entry,
                reservedAt: reservationDate
            )
        } catch {
            utxoStore.release(utxoSet)
            throw error
        }
    }
    
    func releaseSpendReservation(_ reservation: SpendReservation, outcome: SpendReservation.Outcome) async throws {
        guard let state = removeReservationState(matching: reservation) else {
            return
        }

        try await finalizeRelease(for: state, outcome: outcome)
    }

    func completeSpendReservation(_ reservation: SpendReservation) async throws {
        guard let state = removeReservationState(matching: reservation) else {
            throw OpalBase.Address.Book.Error.spendReservationNotFound
        }

        guard utxoStore.containsExact(state.utxos) else {
            try await finalizeRelease(for: state, outcome: .cancelled)
            throw OpalBase.Address.Book.Error.utxoNotFound
        }

        try await finalizeRelease(for: state, outcome: .completed)
    }
    
    func forceReleaseSpendReservation(identifier: UUID,
                                      outcome: SpendReservation.Outcome = .cancelled) async throws -> SpendReservation? {
        guard let state = removeReservationState(for: identifier) else {
            return nil
        }
        
        let reservation = SpendReservation(id: identifier,
                                           changeEntry: state.entry,
                                           reservedAt: state.reservedAt)
        
        try await finalizeRelease(for: state, outcome: outcome)
        
        return reservation
    }
    
    func releaseExpiredSpendReservations(olderThan tolerance: TimeInterval,
                                         currentDate: Date = Date.now) async throws -> [SpendReservation] {
        let expiredStates = spendReservationStates.filter { _, state in
            currentDate.timeIntervalSince(state.reservedAt) >= tolerance
        }
        
        var releasedReservations: [SpendReservation] = .init()
        for (identifier, state) in expiredStates {
            _ = state
            guard let removedState = removeReservationState(for: identifier) else { continue }
            
            let reservation = SpendReservation(id: identifier,
                                               changeEntry: removedState.entry,
                                               reservedAt: removedState.reservedAt)
            
            try await finalizeRelease(for: removedState, outcome: .cancelled)
            releasedReservations.append(reservation)
        }
        
        return releasedReservations
    }
    
    func readActiveSpendReservations() -> [SpendReservation] {
        spendReservationStates.map { element in
            SpendReservation(id: element.key,
                             changeEntry: element.value.entry,
                             reservedAt: element.value.reservedAt)
        }
    }
    
    private func finalizeRelease(for state: SpendReservation.State,
                                 outcome: SpendReservation.Outcome) async throws {
        let shouldKeepUsed: Bool
        switch outcome {
        case .completed:
            utxoStore.remove(Array(state.utxos))
            shouldKeepUsed = true
        case .cancelled:
            utxoStore.release(state.utxos)
            shouldKeepUsed = state.hasBeenUsedPreviously
        }
        
        let updatedEntry = try releaseReservation(address: state.entry.address,
                                                  shouldKeepUsed: shouldKeepUsed)
        
        if !shouldKeepUsed {
            try await generateEntriesIfNeeded(for: updatedEntry.derivationPath.usage)
        }
    }

    private func removeReservationState(matching reservation: SpendReservation) -> SpendReservation.State? {
        guard let state = spendReservationStates[reservation.id],
              state.reservedAt == reservation.reservationDate else {
            return nil
        }

        return removeReservationState(for: reservation.id)
    }

    private func reserveFreshChangeEntry(
        preferred changeEntry: Entry
    ) async throws -> (entry: Entry, hasBeenUsedPreviously: Bool) {
        let candidateEntry: Entry
        if let currentEntry = findEntry(for: changeEntry.address),
           currentEntry.isUsed == false,
           currentEntry.isReserved == false {
            candidateEntry = currentEntry
        } else {
            candidateEntry = try await selectNextEntry(for: changeEntry.derivationPath.usage)
        }

        let reservedEntry = try await reserveEntryMaintainingGap(candidateEntry)
        return (
            entry: reservedEntry,
            hasBeenUsedPreviously: candidateEntry.isUsed
        )
    }
}
