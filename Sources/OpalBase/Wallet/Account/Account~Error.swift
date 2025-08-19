// Account+Error.swift

import Foundation

extension Account {
    public enum Error: Swift.Error {
        case balanceFetchTimeout(Address)
    }
}
