// OpalBase+Address+Book~Mosaic.swift

#if os(macOS)
extension _OpalBase.Address.Book {
    func reserveMosaicReceivingEntry(
        maintainingGapWith maintainGap: (@Sendable () async throws -> Void)? = nil
    ) async throws -> Entry {
        let candidateEntry = try await selectNextEntry(for: .receiving)
        let reservedEntry = try reserveEntry(address: candidateEntry.address)
        do {
            if let maintainGap {
                try await maintainGap()
            } else {
                try await generateEntriesIfNeeded(for: .receiving)
            }
            return reservedEntry
        } catch {
            _ = try? releaseReservation(
                address: reservedEntry.address,
                shouldKeepUsed: true
            )
            throw error
        }
    }
}
#endif
