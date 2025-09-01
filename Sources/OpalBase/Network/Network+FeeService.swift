// Network+FeeService.swift

import Foundation

extension Network {
    public actor FeeService {
        public protocol Provider: Sendable {
            func poll() async throws -> Double
        }
        
        private let provider: Provider
        private let halfLife: TimeInterval
        private let now: @Sendable () -> Date
        private var cachedRate: Double?
        private var lastUpdate: Date?
        
        public init(provider: Provider, halfLife: TimeInterval = 600, now: @escaping @Sendable () -> Date = Date.init) {
            self.provider = provider
            self.halfLife = halfLife
            self.now = now
        }
        
        public func currentFeeRate() async throws -> Double {
            let fresh: Double
            do {
                fresh = try await provider.poll()
            } catch {
                throw Error.pollingFailed(error)
            }
            let now = self.now()
            let rate: Double
            if let previous = cachedRate, let last = lastUpdate {
                let alpha = 1 - pow(0.5, now.timeIntervalSince(last) / halfLife)
                rate = previous + alpha * (fresh - previous)
            } else {
                rate = fresh
            }
            cachedRate = rate
            lastUpdate = now
            return rate
        }
    }
}

extension Network.FeeService {
    public enum Error: Swift.Error, Sendable {
        case pollingFailed(Swift.Error)
    }
}

extension Network.FeeService.Error: Equatable {
    public static func == (lhs: Network.FeeService.Error, rhs: Network.FeeService.Error) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
