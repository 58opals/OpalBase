// OpalBase+Cancellation.swift

import Foundation
import SwiftFulcrum

enum OpalBaseCancellation {
    static func isCancellationError(_ error: Swift.Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let failure = error as? OpalBase.Network.Error {
            return failure.reason == .cancelled
        }

        if let fulcrumError = error as? SwiftFulcrum.Client.Error {
            switch fulcrumError {
            case .client(.cancelled):
                return true
            case .client(.unknown(let underlying)):
                return underlying.map(isCancellationError) ?? false
            default:
                return false
            }
        }

        let nsError = error as NSError
        return (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
            || nsError.domain == String(reflecting: CancellationError.self)
    }
}
