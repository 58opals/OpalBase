// Account+Monitor.swift

import Foundation

extension Account {
    public actor Monitor {
        private var cancelHandlers: [() async -> Void] = .init()
        
        public func stop() async {
            for cancelHandler in cancelHandlers { await cancelHandler() }
            cancelHandlers.removeAll()
        }
        
        func storeCancel(_ cancel: @escaping (() async -> Void)) async {
            cancelHandlers.append(cancel)
        }
    }
}
