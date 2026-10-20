import Foundation

extension _OpalBase.Network {
    /// Synchronous authorization retained through the final transport handoff.
    public struct TransactionSendAuthorization: Sendable {
        public enum Failure: Swift.Error, Sendable, Equatable {
            case unavailable
            case notAuthorized
        }

        private let check: @Sendable () -> Bool

        public init(isAuthorized: @escaping @Sendable () -> Bool) {
            check = isAuthorized
        }

        public func isAuthorized() -> Bool { check() }

        public func requireAuthorized() throws {
            guard check() else { throw Failure.notAuthorized }
        }
    }
}
