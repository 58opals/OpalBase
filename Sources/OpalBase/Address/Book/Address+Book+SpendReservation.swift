// Address+Book+SpendReservation.swift

import Foundation

extension Address.Book {
    struct SpendReservation: Identifiable, Sendable {
        enum Outcome {
            case completed
            case cancelled
        }
        
        struct State: Sendable {
            let utxos: Set<Transaction.Output.Unspent>
            let entry: Entry
            let previousUsageStatus: Bool
            let reservedAt: Date
        }
        
        let id: UUID
        public let changeEntry: Entry
        public let reservationDate: Date
        
        init(id: UUID, changeEntry: Entry, reservedAt: Date) {
            self.id = id
            self.changeEntry = changeEntry
            self.reservationDate = reservedAt
        }
    }
}

extension Address.Book {
    func reserveSpend(utxos: [Transaction.Output.Unspent], changeEntry: Entry) async throws -> SpendReservation {
        let identifier = UUID()
        let utxoSet = Set(utxos)
        let reservationDate = Date()
        
        do {
            try utxoStore.reserve(utxoSet)
        } catch {
            throw error
        }
        
        let reservedEntry = try reserveEntry(address: changeEntry.address)
        try await generateEntriesIfNeeded(for: reservedEntry.derivationPath.usage)
        
        spendReservationStates[identifier] = SpendReservation.State(utxos: utxoSet,
                                                                    entry: reservedEntry,
                                                                    previousUsageStatus: changeEntry.isUsed,
                                                                    reservedAt: reservationDate)
        
        return SpendReservation(id: identifier, changeEntry: reservedEntry, reservedAt: reservationDate)
    }
    
    func releaseSpendReservation(_ reservation: SpendReservation, outcome: SpendReservation.Outcome) async throws {
        guard let state = spendReservationStates.removeValue(forKey: reservation.id) else {
            return
        }
        
        try await finalizeRelease(for: state, outcome: outcome)
    }
    
    func forceReleaseSpendReservation(identifier: UUID,
                                      outcome: SpendReservation.Outcome = .cancelled) async throws -> SpendReservation? {
        guard let state = spendReservationStates.removeValue(forKey: identifier) else {
            return nil
        }
        
        let reservation = SpendReservation(id: identifier,
                                           changeEntry: state.entry,
                                           reservedAt: state.reservedAt)
        
        try await finalizeRelease(for: state, outcome: outcome)
        
        return reservation
    }
    
    func releaseExpiredSpendReservations(olderThan tolerance: TimeInterval,
                                         currentDate: Date = Date()) async throws -> [SpendReservation] {
        let expiredStates = spendReservationStates.filter { _, state in
            currentDate.timeIntervalSince(state.reservedAt) >= tolerance
        }
        
        var releasedReservations: [SpendReservation] = []
        for (identifier, state) in expiredStates {
            _ = state
            
            guard let removedState = spendReservationStates.removeValue(forKey: identifier) else { continue }
            
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
        utxoStore.release(state.utxos)
        
        let shouldKeepUsed: Bool
        switch outcome {
        case .completed:
            shouldKeepUsed = true
        case .cancelled:
            shouldKeepUsed = state.previousUsageStatus
        }
        
        let updatedEntry = try releaseReservation(address: state.entry.address,
                                                  shouldKeepUsed: shouldKeepUsed)
        
        if !shouldKeepUsed {
            try await generateEntriesIfNeeded(for: updatedEntry.derivationPath.usage)
        }
    }
}
