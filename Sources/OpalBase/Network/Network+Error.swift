// Network+Error.swift

import Foundation

extension Network {
    public enum Error: Swift.Error, Sendable {
        case probeFailed(URL, Swift.Error)
        case unhealthyPool
    }
}

extension Network.Error: Equatable {
    public static func == (lhs: Network.Error, rhs: Network.Error) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
