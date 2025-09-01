// Network+Telemetry_.swift

import Foundation

extension Network {
    public protocol Telemetry: Sendable {
        func record(_ metric: Metric) async
    }
}

extension Network {
    public struct Metric: Sendable {
        public let name: String
        public let duration: TimeInterval
        public let success: Bool

        public init(name: String, duration: TimeInterval, success: Bool) {
            self.name = name
            self.duration = duration
            self.success = success
        }
    }
}
