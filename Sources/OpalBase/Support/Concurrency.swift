// Concurrency.swift

import Foundation

enum Concurrency {
    enum Tuning {
        static let maximumConcurrentNetworkRequests = 8
    }
    
    enum Error: Swift.Error {
        case missingMappingResult
    }
}

// MARK: - Collection_+

extension Collection where Element: Sendable {
    func mapConcurrently<Transformed: Sendable>(
        limit: Int = Concurrency.Tuning.maximumConcurrentNetworkRequests,
        transformError: @escaping @Sendable (Element, Swift.Error) -> Swift.Error = { _, error in error },
        _ transform: @escaping @Sendable (Element) async throws -> Transformed
    ) async throws -> [Transformed] {
        guard !isEmpty else { return .init() }
        
        let elementCount = count
        let maximumConcurrentTasks = Swift.max(1, Swift.min(limit, elementCount))
        var iterator = self.enumerated().makeIterator()
        let initialTaskCount = Swift.min(maximumConcurrentTasks, elementCount)
        
        var results: [Transformed?] = Array(repeating: nil, count: elementCount)
        
        try await withThrowingTaskGroup(of: (Int, Transformed).self) { group in
            func addTask() {
                guard let (index, element) = iterator.next() else { return }
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        return (index, try await transform(element))
                    } catch {
                        throw transformError(element, error)
                    }
                }
            }
            
            for _ in 0..<initialTaskCount {
                addTask()
            }
            
            while let (index, value) = try await group.next() {
                results[index] = value
                
                addTask()
            }
        }
        
        return try unwrapResults(results)
    }
    
    private func unwrapResults<Transformed>(_ results: [Transformed?]) throws -> [Transformed] {
        var unwrapped: [Transformed] = .init()
        unwrapped.reserveCapacity(results.count)
        
        for result in results {
            guard let value = result else {
                throw Concurrency.Error.missingMappingResult
            }
            unwrapped.append(value)
        }
        
        return unwrapped
    }
}
