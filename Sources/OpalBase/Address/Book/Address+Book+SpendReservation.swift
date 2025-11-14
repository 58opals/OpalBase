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
        let utxoSet = Set(utxos)
        
        if let existingReservation = findMatchingReservation(for: utxoSet) {
            let refreshedDate = Date()
            let refreshedState = SpendReservation.State(utxos: existingReservation.state.utxos,
                                                        entry: existingReservation.state.entry,
                                                        previousUsageStatus: existingReservation.state.previousUsageStatus,
                                                        reservedAt: refreshedDate)
            spendReservationStates[existingReservation.identifier] = refreshedState
            scheduleAutomaticSpendReservationRelease(for: existingReservation.identifier)
            
            return SpendReservation(id: existingReservation.identifier,
                                    changeEntry: refreshedState.entry,
                                    reservedAt: refreshedDate)
        }
        
        let identifier = UUID()
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
        
        scheduleAutomaticSpendReservationRelease(for: identifier)
        
        return SpendReservation(id: identifier, changeEntry: reservedEntry, reservedAt: reservationDate)
    }
    
    func releaseSpendReservation(_ reservation: SpendReservation, outcome: SpendReservation.Outcome) async throws {
        guard let state = removeReservationState(for: reservation.id) else {
            return
        }
        
        try await finalizeRelease(for: state, outcome: outcome)
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
                                         currentDate: Date = Date()) async throws -> [SpendReservation] {
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

// MARK: - Helpers
private extension Address.Book {
    func findMatchingReservation(for utxos: Set<Transaction.Output.Unspent>) -> (identifier: UUID, state: SpendReservation.State)? {
        spendReservationStates.first { _, state in
            state.utxos == utxos
        }
        .map { element in
            (identifier: element.key, state: element.value)
        }
    }
    
    func removeReservationState(for identifier: UUID) -> SpendReservation.State? {
        cancelAutomaticSpendReservationRelease(for: identifier)
        return spendReservationStates.removeValue(forKey: identifier)
    }
    
    func scheduleAutomaticSpendReservationRelease(for identifier: UUID) {
        guard spendReservationExpirationInterval > 0 else { return }
        
        cancelAutomaticSpendReservationRelease(for: identifier)
        
        let nanoseconds = convertToNanoseconds(spendReservationExpirationInterval)
        guard nanoseconds > 0 else { return }
        
        let releaseTask = Task<Void, Never> { [nanoseconds] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            _ = try? await self.forceReleaseSpendReservation(identifier: identifier, outcome: .cancelled)
        }
        
        spendReservationReleaseTasks[identifier] = releaseTask
    }
    
    func cancelAutomaticSpendReservationRelease(for identifier: UUID) {
        guard let task = spendReservationReleaseTasks.removeValue(forKey: identifier) else { return }
        task.cancel()
    }
    
    func convertToNanoseconds(_ interval: TimeInterval) -> UInt64 {
        guard interval > 0 else { return 0 }
        
        let nanosecondsPerSecond: Double = 1_000_000_000
        let rawValue = interval * nanosecondsPerSecond
        if rawValue >= Double(UInt64.max) {
            return UInt64.max
        }
        
        return UInt64(rawValue)
    }
}

extension Address.Book {
    func clearSpendReservationState() {
        for task in spendReservationReleaseTasks.values {
            task.cancel()
        }
        
        spendReservationReleaseTasks.removeAll()
        spendReservationStates.removeAll()
    }
}
