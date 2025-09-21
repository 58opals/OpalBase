// RequestRouter.swift

import Foundation

public actor RequestRouter<RequestValue: Hashable & Sendable> {
    private let configuration: Configuration
    private let instrumentation: Instrumentation
    private var queue: [Request] = .init()
    private var queuedIndices: [Key: Int] = .init()
    private var queueIndicesKeys: [Key] { Array(queuedIndices.keys) }
    private var activeRequests: [Key: ActiveRequest] = .init()
    private var isSuspended = false
    private var nextPermittedStart: ContinuousClock.Instant?
    
    private var scheduledResume: Task<Void, Never>?
    private var scheduledResumeDeadline: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private var retryBudgetState: RetryBudget.State
    
    public init(configuration: Configuration = .init(),
                instrumentation: Instrumentation = .init())
    {
        precondition(configuration.maximumConcurrentRequests > 0,
                     "maximumConcurrentRequests must be at least 1")
        self.configuration = configuration
        self.instrumentation = instrumentation
        self.retryBudgetState = configuration.retryBudget.makeState(clock: clock)
    }
    
    public func handle(for rawValue: RequestValue) -> Handle {
        Handle(router: self, key: .init(rawValue: rawValue))
    }
    
    public func cancelAll() {
        let cancellation = CancellationError()
        
        scheduledResume?.cancel()
        scheduledResume = nil
        scheduledResumeDeadline = nil
        
        let requests = queue
        queue.removeAll()
        queuedIndices.removeAll()
        instrumentation.queueDepthDidChange(queue.count)
        for request in requests {
            request.onCancellation?(cancellation)
        }
        
        let keys = activeRequests.keys
        for key in keys {
            if var activeRequest = activeRequests[key] {
                let replacement = activeRequest.replacement
                activeRequest.replacement = nil
                activeRequest.task.cancel()
                replacement?.onCancellation?(cancellation)
                activeRequests[key] = activeRequest
            }
        }
    }
    
    public func suspend() {
        isSuspended = true
        scheduledResume?.cancel()
        scheduledResume = nil
        scheduledResumeDeadline = nil
    }
    
    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        nextPermittedStart = nil
        tryStartNext()
    }
    
    func enqueue(key: Key,
                 priority: TaskPriority?,
                 retryPolicy: RetryPolicy,
                 onCancellation: (@Sendable (CancellationError) -> Void)? = nil,
                 onFailure: (@Sendable (Swift.Error) -> Void)? = nil,
                 operation: @escaping @Sendable () async throws -> Void)
    {
        let now = clock.now
        let request = Request(key: key,
                              priority: priority,
                              retryPolicy: retryPolicy,
                              operation: operation,
                              onCancellation: onCancellation,
                              onFailure: onFailure,
                              enqueuedAt: now,
                              attempt: 0,
                              earliestStart: now)
        schedule(request)
    }
    
    func perform<Value>(key: Key,
                        priority: TaskPriority?,
                        retryPolicy: RetryPolicy,
                        operation: @escaping @Sendable () async throws -> Value) async throws -> Value
    {
        try await withCheckedThrowingContinuation { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                await self.enqueue(key: key,
                                   priority: priority,
                                   retryPolicy: retryPolicy,
                                   onCancellation: { continuation.resume(throwing: $0) },
                                   onFailure: { continuation.resume(throwing: $0) }) { [weak self] in
                    guard self != nil else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    
                    do {
                        let value = try await operation()
                        continuation.resume(returning: value)
                    } catch let cancellation as CancellationError {
                        continuation.resume(throwing: cancellation)
                        throw cancellation
                    } catch {
                        throw error
                    }
                }
            }
        }
    }
    
    func cancel(key: Key) {
        let cancellation = CancellationError()
        
        if let index = queuedIndices.removeValue(forKey: key) {
            let removed = queue.remove(at: index)
            removed.onCancellation?(cancellation)
            
            for existingKey in queueIndicesKeys {
                if let currentIndex = queuedIndices[existingKey], currentIndex > index {
                    queuedIndices[existingKey] = currentIndex - 1
                }
            }
            instrumentation.queueDepthDidChange(queue.count)
        }
        
        if var activeRequest = activeRequests[key] {
            let replacement = activeRequest.replacement
            activeRequest.replacement = nil
            activeRequests[key] = activeRequest
            replacement?.onCancellation?(cancellation)
            activeRequest.task.cancel()
        }
        
        tryStartNext()
    }
    
    private func schedule(_ request: Request, preferFront: Bool = false) {
        if var activeRequest = activeRequests[request.key] {
            if let existing = activeRequest.replacement {
                existing.onCancellation?(CancellationError())
            }
            activeRequest.replacement = request
            activeRequests[request.key] = activeRequest
            return
        }
        
        if let index = queuedIndices[request.key] {
            let replaced = queue[index]
            queue[index] = request
            replaced.onCancellation?(CancellationError())
            return
        }
        
        if preferFront {
            queue.insert(request, at: 0)
            for key in queueIndicesKeys {
                if let index = queuedIndices[key] {
                    queuedIndices[key] = index + 1
                }
            }
            queuedIndices[request.key] = 0
        } else {
            queue.append(request)
            queuedIndices[request.key] = queue.count - 1
        }
        
        instrumentation.queueDepthDidChange(queue.count)
        tryStartNext()
    }
    
    func dequeue() -> Request? {
        guard !queue.isEmpty else { return nil }
        let request = queue.removeFirst()
        queuedIndices.removeValue(forKey: request.key)
        
        for key in queueIndicesKeys {
            if let index = queuedIndices[key], index > 0 {
                queuedIndices[key] = index - 1
            }
        }
        
        instrumentation.queueDepthDidChange(queue.count)
        return request
    }
    
    private func tryStartNext() {
        guard !isSuspended else { return }
        guard activeRequests.count < configuration.maximumConcurrentRequests else { return }
        guard let pending = queue.first else { return }
        
        let now = clock.now
        let earliestStart = max(pending.earliestStart, nextPermittedStart ?? pending.earliestStart)
        if now < earliestStart {
            scheduleResume(at: earliestStart)
            return
        }
        
        scheduledResume?.cancel()
        scheduledResume = nil
        scheduledResumeDeadline = nil
        
        guard let request = dequeue() else { return }
        start(request)
        tryStartNext()
    }
    
    private func scheduleResume(at instant: ContinuousClock.Instant) {
        if let deadline = scheduledResumeDeadline, deadline <= instant { return }
        scheduledResume?.cancel()
        scheduledResumeDeadline = instant
        scheduledResume = Task { [weak self] in
            guard let self else { return }
            
            do {
                try await self.clock.sleep(until: instant, tolerance: .zero)
            } catch {
                return
            }
            
            await self.resumeProcessing()
        }
    }
    
    private func resumeProcessing() {
        scheduledResume = nil
        scheduledResumeDeadline = nil
        tryStartNext()
    }
    
    private func start(_ request: Request) {
        let startInstant = clock.now
        nextPermittedStart = startInstant.advanced(by: configuration.minimumDelayBetweenRequests)
        let waitDuration = request.enqueuedAt.duration(to: startInstant)
        instrumentation.waitTimeMeasured(for: request.key.rawValue,
                                         attempt: request.attempt,
                                         wait: waitDuration)
        
        let task = Task(priority: request.priority) {
            do {
                try await request.operation()
                await self.handleCompletion(for: request.key,
                                            request: request,
                                            result: .success(()))
            } catch {
                await self.handleCompletion(for: request.key,
                                            request: request,
                                            result: .failure(error))
            }
        }
        
        activeRequests[request.key] = .init(request: request,
                                            task: task,
                                            replacement: nil)
    }
    
    private func handleCompletion(for key: Key,
                                  request: Request,
                                  result: Result<Void, Swift.Error>) async
    {
        guard var activeRequest = activeRequests.removeValue(forKey: key) else { return }
        let replacement = activeRequest.replacement
        activeRequest.replacement = nil
        
        switch result {
        case .success:
            if let replacement { schedule(replacement, preferFront: true) }
        case .failure(let error):
            if let cancellation = error as? CancellationError {
                request.onCancellation?(cancellation)
            } else {
                if let replacement {
                    schedule(replacement, preferFront: true)
                    request.onFailure?(error)
                    instrumentation.requestFailed(for: request.key.rawValue,
                                                  attempt: request.attempt,
                                                  error: error)
                } else if let retryRequest = makeRetryRequest(from: request, error: error) {
                    instrumentation.requestRetried(for: request.key.rawValue,
                                                   attempt: retryRequest.attempt,
                                                   error: error)
                    schedule(retryRequest)
                } else {
                    request.onFailure?(error)
                    instrumentation.requestFailed(for: request.key.rawValue,
                                                  attempt: request.attempt,
                                                  error: error)
                }
            }
        }
        
        tryStartNext()
    }
    
    private func makeRetryRequest(from request: Request, error: Swift.Error) -> Request? {
        guard request.retryPolicy == .retry else { return nil }
        let nextAttempt = request.attempt + 1
        guard nextAttempt <= configuration.retryBudget.maximumRetryCount else { return nil }
        
        let now = clock.now
        var totalDelay = configuration.backoff.delay(forAttempt: nextAttempt)
        if configuration.jitterRange.upperBound > 0 {
            let jitter = Double.random(in: configuration.jitterRange)
            totalDelay += Duration.seconds(jitter)
        }
        let budgetDelay = retryBudgetState.nextDelay(now: now)
        totalDelay += budgetDelay
        
        let earliestStart = now.advanced(by: totalDelay)
        return Request(key: request.key,
                       priority: request.priority,
                       retryPolicy: request.retryPolicy,
                       operation: request.operation,
                       onCancellation: request.onCancellation,
                       onFailure: request.onFailure,
                       enqueuedAt: now,
                       attempt: nextAttempt,
                       earliestStart: earliestStart)
    }
}

extension RequestRouter {
    public struct Instrumentation: Sendable {
        private let queueDepthChangeHandler: @Sendable (Int) -> Void
        private let waitTimeHandler: @Sendable (RequestValue, Int, Duration) -> Void
        private let retryHandler: @Sendable (RequestValue, Int, Swift.Error) -> Void
        private let failureHandler: @Sendable (RequestValue, Int, Swift.Error) -> Void
        
        public init(onQueueDepthDidChange: @escaping @Sendable (Int) -> Void = { _ in },
                    onWaitTimeMeasured: @escaping @Sendable (RequestValue, Int, Duration) -> Void = { _, _, _ in },
                    onRetry: @escaping @Sendable (RequestValue, Int, Swift.Error) -> Void = { _, _, _ in },
                    onFailure: @escaping @Sendable (RequestValue, Int, Swift.Error) -> Void = { _, _, _ in })
        {
            self.queueDepthChangeHandler = onQueueDepthDidChange
            self.waitTimeHandler = onWaitTimeMeasured
            self.retryHandler = onRetry
            self.failureHandler = onFailure
        }
        
        func queueDepthDidChange(_ depth: Int) {
            queueDepthChangeHandler(depth)
        }
        
        func waitTimeMeasured(for value: RequestValue, attempt: Int, wait: Duration) {
            waitTimeHandler(value, attempt, wait)
        }
        
        func requestRetried(for value: RequestValue, attempt: Int, error: Swift.Error) {
            retryHandler(value, attempt, error)
        }
        
        func requestFailed(for value: RequestValue, attempt: Int, error: Swift.Error) {
            failureHandler(value, attempt, error)
        }
    }
}
