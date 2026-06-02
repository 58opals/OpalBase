// OpalBase+Account+CashFusionReceivingEntryReservation.swift

#if os(macOS)
extension _OpalBase.Address.Book {
    func reserveCashFusionReceivingEntries(
        count: Int
    ) async throws -> [OpalBase.Address.Book.Entry] {
        var reservedEntries: [OpalBase.Address.Book.Entry] = []
        reservedEntries.reserveCapacity(count)

        do {
            for _ in 0..<count {
                let reservedEntry = try await reserveNextEntry(for: .receiving)
                reservedEntries.append(reservedEntry)
            }
        } catch {
            try await releaseCashFusionReceivingEntries(
                reservedEntries,
                shouldKeepUsed: false
            )
            throw error
        }

        return reservedEntries
    }

    func releaseCashFusionReceivingEntries(
        _ entries: [OpalBase.Address.Book.Entry],
        shouldKeepUsed: Bool
    ) async throws {
        var firstError: Swift.Error?
        var releasedAddresses = Set<OpalBase.Address>()

        for entry in entries where releasedAddresses.insert(entry.address).inserted {
            do {
                _ = try releaseReservation(
                    address: entry.address,
                    shouldKeepUsed: shouldKeepUsed
                )
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }
}
#endif
