// Network+Telemetry.swift

import Foundation

extension Network.FulcrumSession {
    public enum Telemetry {}
}

extension Network.FulcrumSession.Telemetry {
    public struct AccountContext: Sendable, Equatable {
        public let accountIdentifier: Data
        public let unhardenedIndex: UInt32
        
        public init(accountIdentifier: Data, unhardenedIndex: UInt32) {
            self.accountIdentifier = accountIdentifier
            self.unhardenedIndex = unhardenedIndex
        }
    }
}

extension Network.FulcrumSession.Telemetry {
    public enum Event: Sendable, Equatable {
        case queueDepthDidChange(AccountContext, depth: Int)
        case requestDidRetry(AccountContext, request: Account.Request, attempt: Int, failureDescription: String)
        case activeServerDidChange(URL?)
    }
}

extension Network.FulcrumSession {
    public func makeTelemetryStream() -> AsyncStream<Telemetry.Event> {
        AsyncStream { continuation in
            registerTelemetryContinuation(continuation)
        }
    }
}

extension Network.FulcrumSession {
    func registerTelemetryContinuation(_ continuation: AsyncStream<Telemetry.Event>.Continuation) {
        let identifier = UUID()
        
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeTelemetryContinuation(for: identifier) }
        }
        
        telemetryContinuations[identifier] = continuation
    }
    
    func removeTelemetryContinuation(for identifier: UUID) {
        telemetryContinuations.removeValue(forKey: identifier)
    }
    
    func emitTelemetry(_ event: Telemetry.Event) {
        guard !telemetryContinuations.isEmpty else { return }
        let continuations = Array(telemetryContinuations.values)
        
        for continuation in continuations {
            continuation.yield(event)
        }
    }
}

extension Network.FulcrumSession {
    func ensureTelemetryInstalled(for account: Account) async {
        let identifier = account.id
        if telemetryAccountContexts[identifier] != nil { return }
        
        let context = await makeTelemetryAccountContext(for: account, identifier: identifier)
        telemetryAccountContexts[identifier] = context
        
        let instrumentation = makeAccountRequestRouterInstrumentation(for: account, context: context)
        await account.updateRequestRouterInstrumentation(instrumentation)
    }
}

private extension Network.FulcrumSession {
    func makeTelemetryAccountContext(for account: Account, identifier: Data) async -> Telemetry.AccountContext {
        let unhardenedIndex = await account.unhardenedIndex
        return .init(accountIdentifier: identifier, unhardenedIndex: unhardenedIndex)
    }
    
    func makeAccountRequestRouterInstrumentation(for account: Account,
                                                 context: Telemetry.AccountContext) -> RequestRouter<Account.Request>.Instrumentation
    {
        RequestRouter<Account.Request>.Instrumentation(
            didChangeQueueDepth: { [weak self] depth in
                guard let self else { return }
                Task { await self.recordQueueDepthChange(for: context, depth: depth) }
            },
            didMeasureWaitTime: { _, _, _ in },
            didRetryRequest: { [weak self] request, attempt, error in
                guard let self else { return }
                let failureDescription = error.localizedDescription
                Task {
                    await account.recordOutboxRetry(for: request,
                                                    failureDescription: failureDescription)
                    await self.recordRequestRetry(for: context,
                                                  request: request,
                                                  attempt: attempt,
                                                  failureDescription: failureDescription)
                }
            },
            didFailRequest: { request, _, error in
                let failureDescription = error.localizedDescription
                Task {
                    await account.recordOutboxFailure(for: request,
                                                      failureDescription: failureDescription)
                }
            }
        )
    }
    
    func recordQueueDepthChange(for context: Telemetry.AccountContext, depth: Int) async {
        emitTelemetry(.queueDepthDidChange(context, depth: depth))
    }
    
    func recordRequestRetry(for context: Telemetry.AccountContext,
                            request: Account.Request,
                            attempt: Int,
                            failureDescription: String) async {
        emitTelemetry(.requestDidRetry(context,
                                       request: request,
                                       attempt: attempt,
                                       failureDescription: failureDescription))
    }
}
