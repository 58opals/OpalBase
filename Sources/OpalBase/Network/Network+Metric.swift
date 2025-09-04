// Network+Metric.swift

extension Network {
    public struct Metric: Sendable {
        public let name: String
        public let duration: TimeInterval
        public let success: Bool
    }
}
