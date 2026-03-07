// OpalBase.Address+BookActor~ReservationState.swift

import Foundation

// MARK: - State
extension _OpalBase.Address.Book {
    func findMatchingReservation(for utxos: Set<OpalBase.Transaction.OutputModel.UnspentModel>) -> (identifier: UUID, state: SpendReservationModel.State)? {
        spendReservationStates.first { _, state in
            state.utxos == utxos
        }
        .map { element in
            (identifier: element.key, state: element.value)
        }
    }
    
    func removeReservationState(for identifier: UUID) -> SpendReservationModel.State? {
        cancelAutomaticSpendReservationRelease(for: identifier)
        return spendReservationStates.removeValue(forKey: identifier)
    }
}

extension _OpalBase.Address.Book {
    func clearSpendReservationState() {
        for task in spendReservationReleaseTasks.values {
            task.cancel()
        }
        
        spendReservationReleaseTasks.removeAll()
        spendReservationStates.removeAll()
    }
}

