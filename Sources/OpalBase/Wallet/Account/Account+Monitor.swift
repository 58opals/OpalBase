// Account+Monitor.swift

import Foundation

extension Account {
    public actor Monitor {
        private var activeConsumerID: UUID?
        private var isMonitoring = false
        
        private var debounceTask: Task<Void, Never>?
        private let debounceInterval: UInt64 = 100_000_000 // 100ms
        
        private var tasks: [Task<Void, Never>] = .init()
        
        func beginMonitoring(consumerID: UUID) throws {
            guard !isMonitoring else { throw Error.monitoringAlreadyRunning }
            isMonitoring = true
            activeConsumerID = consumerID
        }
        
        public func stop(hub: Network.Wallet.SubscriptionHub) async {
            debounceTask?.cancel()
            debounceTask = nil
            for task in tasks { task.cancel() }
            tasks.removeAll()
            if let consumerID = activeConsumerID { await hub.remove(consumerID: consumerID) }
            activeConsumerID = nil
            isMonitoring = false
        }
        
        func scheduleCoalescedEmit(_ emit: @escaping @Sendable () -> Void) {
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: debounceInterval)
                emit()
            }
        }
        
        func storeTask(_ task: Task<Void, Never>) {
            tasks.append(task)
        }
    }
}

extension Account.Monitor {
    public enum Error: Swift.Error {
        case monitoringAlreadyRunning
        case monitoringFailed(Swift.Error)
        case emptyAddresses
    }
}

extension Account.Monitor.Error: Equatable {
    public static func == (lhs: Account.Monitor.Error, rhs: Account.Monitor.Error) -> Bool {
        switch (lhs, rhs) {
        case (.monitoringAlreadyRunning, .monitoringAlreadyRunning),
            (.monitoringFailed, .monitoringFailed),
            (.emptyAddresses, .emptyAddresses):
            return true
        default:
            return false
        }
    }
}
