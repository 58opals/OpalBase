// Address+Book+SpendReservation~AutomaticRelease.swift

import Foundation

extension Address.Book {
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
