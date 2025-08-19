// Account+Monitor+Error.swift

import Foundation

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
