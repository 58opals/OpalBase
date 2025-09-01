// Network+Router+Request.swift

import Foundation

extension Network.Router {
    public actor Request<Request: Hashable & Sendable, Response: Sendable> {
        public typealias Sender = @Sendable (Request) async throws -> Response
        
        private let policy: NetworkPolicy
        private let rateCap: Int
        private let send: Sender
        private let telemetry: Network.Telemetry?
        private var inFlight: [Request: [CheckedContinuation<Response, Swift.Error>]] = [:]
        private var timestamps: [Date] = []
        
        public init(policy: NetworkPolicy,
                    rateCap: Int,
                    telemetry: Network.Telemetry? = nil,
                    send: @escaping Sender) {
            self.policy = policy
            self.rateCap = rateCap
            self.telemetry = telemetry
            self.send = send
        }
        
        public func route(_ request: Request) async throws -> Response {
            if inFlight[request] != nil {
                return try await withCheckedThrowingContinuation { cont in
                    inFlight[request]?.append(cont)
                }
            }
            
            inFlight[request] = []
            do {
                let result = try await perform(request)
                resolve(request, result: .success(result))
                return result
            } catch {
                resolve(request, result: .failure(error))
                throw error
            }
        }
        
        private func perform(_ request: Request) async throws -> Response {
            try enforceRateCap()
            let attempts = policy.retryPolicy.maxAttempts
            let backoff = policy.retryPolicy.backoff
            var lastError: Swift.Error?
            for attempt in 1...attempts {
                let start = Date()
                do {
                    let value = try await withTimeout(seconds: policy.timeouts.read) {
                        try await self.send(request)
                    }
                    await publishMetric(name: String(describing: request), start: start, success: true)
                    return value
                } catch Error.timeout {
                    await publishMetric(name: String(describing: request), start: start, success: false)
                    lastError = Error.timeout
                } catch {
                    await publishMetric(name: String(describing: request), start: start, success: false)
                    lastError = error
                }
                if attempt < attempts {
                    try await Task.sleep(for: .seconds(backoff * Double(attempt)))
                }
            }
            throw Error.underlying(lastError ?? Error.timeout)
        }
        
        private func enforceRateCap() throws {
            let now = Date()
            timestamps = timestamps.filter { now.timeIntervalSince($0) < 1 }
            guard timestamps.count < rateCap else { throw Error.rateLimited }
            timestamps.append(now)
        }
        
        private func resolve(_ request: Request, result: Result<Response, Swift.Error>) {
            guard let continuations = inFlight.removeValue(forKey: request) else { return }
            for continuation in continuations {
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        private func publishMetric(name: String, start: Date, success: Bool) async {
            guard let telemetry else { return }
            let duration = Date().timeIntervalSince(start)
            let metric = Network.Metric(name: name, duration: duration, success: success)
            await telemetry.record(metric)
        }
        
        private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @Sendable @escaping () async throws -> T) async throws -> T {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    try await Task.sleep(for: .seconds(seconds))
                    throw Error.timeout
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        }
    }
}

extension Network.Router.Request {
    public enum Error: Swift.Error, Sendable {
        case timeout
        case rateLimited
        case underlying(Swift.Error)
    }
}

extension Network.Router.Request.Error: Equatable {
    public static func == (lhs: Network.Router.Request<Request, Response>.Error, rhs: Network.Router.Request<Request, Response>.Error) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
