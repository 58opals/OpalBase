// ReusablePaymentAddressStatePersistenceActor.swift

@testable import OpalBase

actor ReusablePaymentAddressStatePersistenceActor {
    private var state: OpalBase.ReusablePaymentAddress.RestorationState?
    private var failingRevision: UInt64?
    private var saveCount = 0

    func loadState()
        -> OpalBase.ReusablePaymentAddress.RestorationState?
    {
        state
    }

    func saveState(
        _ newState: OpalBase.ReusablePaymentAddress.RestorationState,
        replacingRevision expectedRevision: UInt64?
    ) throws {
        guard state?.revision == expectedRevision else {
            throw OpalBase.ReusablePaymentAddress.Error
                .stateRevisionConflict
        }
        if newState.revision == failingRevision {
            throw OpalBase.ReusablePaymentAddress.Error
                .invalidPersistentState
        }
        state = newState
        saveCount += 1
    }

    func failSavingRevision(_ revision: UInt64?) {
        failingRevision = revision
    }

    func readSaveCount() -> Int {
        saveCount
    }

    func makePersistence()
        -> OpalBase.ReusablePaymentAddress.StatePersistence
    {
        .init(
            loadState: { await self.loadState() },
            saveState: { state, revision in
                try await self.saveState(
                    state,
                    replacingRevision: revision
                )
            }
        )
    }
}
