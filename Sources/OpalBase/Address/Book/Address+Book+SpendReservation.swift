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
        }
        
        let id: UUID
        public let changeEntry: Entry
        
        init(id: UUID, changeEntry: Entry) {
            self.id = id
            self.changeEntry = changeEntry
        }
    }
}

extension Address.Book {
    func reserveSpend(utxos: [Transaction.Output.Unspent], changeEntry: Entry) async throws -> SpendReservation {
        let identifier = UUID()
        let utxoSet = Set(utxos)
        
        do {
            try utxoStore.reserve(utxoSet)
        } catch {
            throw error
        }
        
        let reservedEntry = try reserveEntry(address: changeEntry.address)
        try await generateEntriesIfNeeded(for: reservedEntry.derivationPath.usage)
        
        spendReservationStates[identifier] = SpendReservation.State(utxos: utxoSet,
                                                                    entry: reservedEntry,
                                                                    previousUsageStatus: changeEntry.isUsed)
        
        return SpendReservation(id: identifier, changeEntry: reservedEntry)
    }
    
    func releaseSpendReservation(_ reservation: SpendReservation, outcome: SpendReservation.Outcome) async throws {
        guard let state = spendReservationStates.removeValue(forKey: reservation.id) else {
            return
        }
        
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
