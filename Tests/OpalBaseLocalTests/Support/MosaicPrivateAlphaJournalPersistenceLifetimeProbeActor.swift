// MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor.swift

#if os(macOS)
actor MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor {
    private var accessCount = 0

    func recordAccess() {
        accessCount += 1
    }

    func readAccessCount() -> Int {
        accessCount
    }
}
#endif
