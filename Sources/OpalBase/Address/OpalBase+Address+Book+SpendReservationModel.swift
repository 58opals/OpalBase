// OpalBase+Address+Book+SpendReservationModel.swift

import Foundation

extension _OpalBase.Address.Book {
    struct SpendReservationModel: Identifiable, Sendable {
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
                      tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy) async throws -> SpendReservationModel {
        let utxoSet = Set(utxos)
        
        if let existingReservation = findMatchingReservation(for: utxoSet) {
            let refreshedDate = Date.now
            let refreshedState = SpendReservationModel.State(utxos: existingReservation.state.utxos,
                                                        entry: existingReservation.state.entry,
                                                        hasBeenUsedPreviously: existingReservation.state.hasBeenUsedPreviously,
                                                        reservedAt: refreshedDate)
            spendReservationStates[existingReservation.identifier] = refreshedState
            scheduleAutomaticSpendReservationRelease(for: existingReservation.identifier)
            
            return SpendReservationModel(id: existingReservation.identifier,
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
        
        let reservedEntry = try reserveEntry(address: changeEntry.address)
        try await generateEntriesIfNeeded(for: reservedEntry.derivationPath.usage)
        
        spendReservationStates[identifier] = SpendReservationModel.State(utxos: utxoSet,
                                                                    entry: reservedEntry,
                                                                    hasBeenUsedPreviously: changeEntry.isUsed,
                                                                    reservedAt: reservationDate)
        
        scheduleAutomaticSpendReservationRelease(for: identifier)
        
        return SpendReservationModel(id: identifier, changeEntry: reservedEntry, reservedAt: reservationDate)
    }
    
    func releaseSpendReservation(_ reservation: SpendReservationModel, outcome: SpendReservationModel.Outcome) async throws {
        guard let state = removeReservationState(for: reservation.id) else {
            return
        }
        
        try await finalizeRelease(for: state, outcome: outcome)
    }
    
    func forceReleaseSpendReservation(identifier: UUID,
                                      outcome: SpendReservationModel.Outcome = .cancelled) async throws -> SpendReservationModel? {
        guard let state = removeReservationState(for: identifier) else {
            return nil
        }
        
        let reservation = SpendReservationModel(id: identifier,
                                           changeEntry: state.entry,
                                           reservedAt: state.reservedAt)
        
        try await finalizeRelease(for: state, outcome: outcome)
        
        return reservation
    }
    
    func releaseExpiredSpendReservations(olderThan tolerance: TimeInterval,
                                         currentDate: Date = Date.now) async throws -> [SpendReservationModel] {
        let expiredStates = spendReservationStates.filter { _, state in
            currentDate.timeIntervalSince(state.reservedAt) >= tolerance
        }
        
        var releasedReservations: [SpendReservationModel] = .init()
        for (identifier, state) in expiredStates {
            _ = state
            guard let removedState = removeReservationState(for: identifier) else { continue }
            
            let reservation = SpendReservationModel(id: identifier,
                                               changeEntry: removedState.entry,
                                               reservedAt: removedState.reservedAt)
            
            try await finalizeRelease(for: removedState, outcome: .cancelled)
            releasedReservations.append(reservation)
        }
        
        return releasedReservations
    }
    
    func readActiveSpendReservations() -> [SpendReservationModel] {
        spendReservationStates.map { element in
            SpendReservationModel(id: element.key,
                             changeEntry: element.value.entry,
                             reservedAt: element.value.reservedAt)
        }
    }
    
    private func finalizeRelease(for state: SpendReservationModel.State,
                                 outcome: SpendReservationModel.Outcome) async throws {
        utxoStore.release(state.utxos)
        
        let shouldKeepUsed: Bool
        switch outcome {
        case .completed:
            shouldKeepUsed = true
        case .cancelled:
            shouldKeepUsed = state.hasBeenUsedPreviously
        }
        
        let updatedEntry = try releaseReservation(address: state.entry.address,
                                                  shouldKeepUsed: shouldKeepUsed)
        
        if !shouldKeepUsed {
            try await generateEntriesIfNeeded(for: updatedEntry.derivationPath.usage)
        }
    }
}
