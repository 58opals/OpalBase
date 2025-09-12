// Account+Monitor.swift

import Foundation

extension Account {
    public actor Monitor {
        private var cancelHandlers: [() async -> Void] = .init()
        private var isMonitoring = false
        
        func beginMonitoring() throws {
            guard !isMonitoring else { throw Error.monitoringAlreadyRunning }
            isMonitoring = true
        }
        
        public func stop() async {
            for cancelHandler in cancelHandlers { await cancelHandler() }
            cancelHandlers.removeAll()
            isMonitoring = false
        }
        
        func storeCancel(_ cancel: @escaping (() async -> Void)) async {
            cancelHandlers.append(cancel)
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
        lhs.localizedDescription == rhs.localizedDescription
    }
}
