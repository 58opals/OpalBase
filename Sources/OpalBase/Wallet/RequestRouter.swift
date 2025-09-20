// RequestRouter.swift

import Foundation

public actor RequestRouter<RequestValue: Hashable & Sendable> {
    private let configuration: Configuration
    private var queue: [Request] = .init()
    private var queuedIndices: [Key: Int] = .init()
    private var queueIndicesKeys: [Key] { Array(queuedIndices.keys) }
    private var activeRequests: [Key: ActiveRequest] = .init()
    private var processor: Task<Void, Never>?
    private var isSuspended = false
    private let clock = ContinuousClock()
    private var nextPermittedStart: ContinuousClock.Instant?
    
    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }
    
    public func handle(for rawValue: RequestValue) -> Handle {
        Handle(router: self, key: .init(rawValue: rawValue))
    }
    
    public func cancelAll() {
        let cancellation = CancellationError()
        
        let requests = queue
        queue.removeAll()
        queuedIndices.removeAll()
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
    }
    
    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        nextPermittedStart = nil
        startProcessingIfNeeded()
    }
    
    func enqueue(key: Key,
                 priority: TaskPriority?,
                 retryPolicy: RetryPolicy,
                 onCancellation: (@Sendable (CancellationError) -> Void)? = nil,
                 operation: @escaping @Sendable () async throws -> Void) {
        let request = Request(key: key,
                              priority: priority,
                              retryPolicy: retryPolicy,
                              operation: operation,
                              onCancellation: onCancellation)
        schedule(request)
    }
    
    func perform<Value>(key: Key,
                        priority: TaskPriority?,
                        operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                enqueue(key: key,
                        priority: priority,
                        retryPolicy: .discard,
                        onCancellation: { continuation.resume(throwing: $0) }) { [weak self] in
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
                        continuation.resume(throwing: error)
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
        }
        
        if var activeRequest = activeRequests[key] {
            let replacement = activeRequest.replacement
            activeRequest.replacement = nil
            activeRequests[key] = activeRequest
            replacement?.onCancellation?(cancellation)
            activeRequest.task.cancel()
        }
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
        
        startProcessingIfNeeded()
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
        
        return request
    }
    
    private func startProcessingIfNeeded() {
        guard processor == nil, !isSuspended else { return }
        processor = Task { [weak self] in
            await self?.processRequests()
        }
    }
    
    private func processRequests() async {
        defer { processor = nil }
        
        while !Task.isCancelled {
            if isSuspended { break }
            
            guard let request = dequeue() else { break }
            
            do {
                try await waitForRateLimitIfNeeded()
            } catch {
                schedule(request, preferFront: true)
                break
            }
            
            let result = await execute(request)
            let activeRequest = activeRequests.removeValue(forKey: request.key)
            let replacement = activeRequest?.replacement
            
            switch result {
            case .success:
                if let replacement { schedule(replacement, preferFront: true) }
                
            case .failure(let error):
                if let cancellation = error as? CancellationError {
                    request.onCancellation?(cancellation)
                } else {
                    if let replacement {
                        schedule(replacement, preferFront: true)
                    } else if request.retryPolicy == .retry {
                        schedule(request)
                    }
                }
            }
        }
        
        if !queue.isEmpty && !isSuspended && !Task.isCancelled {
            startProcessingIfNeeded()
        }
    }
    
    private func execute(_ request: Request) async -> Result<Void, Swift.Error> {
        let task = Task(priority: request.priority) {
            try await request.operation()
        }
        activeRequests[request.key] = .init(request: request, task: task, replacement: nil)
        
        do {
            try await task.value
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    private func waitForRateLimitIfNeeded() async throws {
        if let next = nextPermittedStart {
            let now = clock.now
            if now < next {
                try await clock.sleep(until: next, tolerance: .zero)
            }
        }
        
        nextPermittedStart = clock.now.advanced(by: configuration.minimumDelayBetweenRequests)
    }
}
