// Account+Monitor.swift

import Foundation

extension Account {
    public actor Monitor {
        private var cancelHandlers: [() async -> Void] = .init()
        private var isMonitoring = false
        
        private var tasks: [Task<Void, Never>] = .init()
        private var debounceTask: Task<Void, Never>?
        private let debounceInterval: UInt64 = 100_000_000 // 100ms
        
        func beginMonitoring() throws {
            guard !isMonitoring else { throw Error.monitoringAlreadyRunning }
            isMonitoring = true
        }
        
        public func stop() async {
            for task in tasks { task.cancel() }
            tasks.removeAll()
            debounceTask?.cancel()
            debounceTask = nil
            for cancelHandler in cancelHandlers { await cancelHandler() }
            cancelHandlers.removeAll()
            isMonitoring = false
        }
        
        func storeCancel(_ cancel: @escaping (() async -> Void)) async {
            cancelHandlers.append(cancel)
        }
        
        func storeTask(_ task: Task<Void, Never>) {
            tasks.append(task)
        }
        
        func scheduleCoalescedEmit(_ emit: @escaping @Sendable () -> Void) {
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: debounceInterval)
                emit()
            }
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
