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
        limit: Int,
        _ transform: @escaping @Sendable (Element) async throws -> Transformed
    ) async throws -> [Transformed] {
        guard !isEmpty else { return .init() }
        
        let maximumConcurrentTasks = Swift.max(1, limit)
        var iterator = self.enumerated().makeIterator()
        let initialTaskCount = Swift.min(maximumConcurrentTasks, count)
        
        return try await withThrowingTaskGroup(of: (Int, Transformed).self) { group in
            for _ in 0..<initialTaskCount {
                guard let (index, element) = iterator.next() else { break }
                group.addTask {
                    try Task.checkCancellation()
                    return (index, try await transform(element))
                }
            }
            
            var results = Array<Transformed?>(repeating: nil, count: count)
            
            while let (index, value) = try await group.next() {
                results[index] = value
                
                if let (nextIndex, nextElement) = iterator.next() {
                    group.addTask {
                        try Task.checkCancellation()
                        return (nextIndex, try await transform(nextElement))
                    }
                }
            }
            
            return try unwrapResults(results)
        }
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
