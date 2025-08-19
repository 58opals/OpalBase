// Account+Snapshot+Error.swift

import Foundation

extension Account.Snapshot {
    enum Error: Swift.Error {
        case missingCombinedData
    }
}
