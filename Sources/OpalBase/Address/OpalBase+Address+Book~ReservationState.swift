// OpalBase+Address+Book~ReservationState.swift

import Foundation

// MARK: - State
extension _OpalBase.Address.Book {
    func findMatchingReservation(for utxos: Set<OpalBase.Transaction.Output.Unspent>) -> (identifier: UUID, state: SpendReservation.State)? {
        spendReservationStates.first { _, state in
            state.utxos.hasExactPayloads(matching: utxos)
        }
        .map { element in
            (identifier: element.key, state: element.value)
        }
    }
    
    func removeReservationState(for identifier: UUID) -> SpendReservation.State? {
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
        utxoStore.releaseAllReservations()
    }
}

private extension Set where Element == OpalBase.Transaction.Output.Unspent {
    func hasExactPayloads(matching other: Self) -> Bool {
        guard count == other.count else {
            return false
        }

        return allSatisfy { expected in
            other.contains { candidate in
                candidate.hasSameOutpointAndPayload(as: expected)
            }
        }
    }
}
