// Network+FulcrumSession.swift

import Foundation
import SwiftFulcrum

extension Network {
    public actor FulcrumSession {
        
    }
}

extension Network.FulcrumSession {
    public enum Error: Swift.Error {
        case sessionAlreadyStarted
        case sessionNotStarted
        case unsupportedServerAddress
        case subscriptionNotFound
        case unexpectedResponse(SwiftFulcrum.Method)
        case failedToRestoreSubscription(Swift.Error)
    }
}

extension Network.FulcrumSession.Error: Equatable {
    public static func == (lhs: Network.FulcrumSession.Error, rhs: Network.FulcrumSession.Error) -> Bool {
        switch (lhs, rhs) {
        case (.sessionAlreadyStarted, .sessionAlreadyStarted),
            (.sessionNotStarted, .sessionNotStarted),
            (.unsupportedServerAddress, .unsupportedServerAddress),
            (.subscriptionNotFound, .subscriptionNotFound):
            return true
        case (.unexpectedResponse(let leftMethod), .unexpectedResponse(let rightMethod)):
            return String(reflecting: leftMethod) == String(reflecting: rightMethod)
        case (.failedToRestoreSubscription(let leftError), .failedToRestoreSubscription(let rightError)):
            return leftError.localizedDescription == rightError.localizedDescription
        default:
            return false
        }
    }
}
