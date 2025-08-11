// Account+Monitor+Error.swift

import Foundation

extension Account.Monitor {
    public enum Error: Swift.Error {
        case monitoringAlreadyRunning
        case monitoringFailed(Swift.Error)
        case emptyAddresses
    }
}
