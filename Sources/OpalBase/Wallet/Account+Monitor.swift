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
