// Collection+ConcurrentMap.swift

import Foundation

// MARK: - Collection+ConcurrentMap

extension Collection where Element: Sendable {
    func mapConcurrently<Transformed: Sendable>(
        maximumConcurrentTasks: Int = 8,
        transformError: @escaping @Sendable (Element, Swift.Error) -> Swift.Error = { _, error in error },
        _ transform: @escaping @Sendable (Element) async throws -> Transformed
    ) async throws -> [Transformed] {
        let elementCount = count
        let boundedTaskCount = Swift.max(1, Swift.min(maximumConcurrentTasks, elementCount))
        var iterator = self.enumerated().makeIterator()
        
        var results: [Transformed?] = Array(repeating: nil, count: elementCount)
        
        try await withThrowingTaskGroup(of: (Int, Transformed).self) { group in
            func addTask() {
                guard let (index, element) = iterator.next() else { return }
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        return (index, try await transform(element))
                    } catch {
                        if error.isCancellationError {
                            throw error
                        }
                        throw transformError(element, error)
                    }
                }
            }
            
            for _ in 0..<boundedTaskCount {
                addTask()
            }
            
            while let (index, value) = try await group.next() {
                results[index] = value
                
                addTask()
            }
        }
        
        return try results.map { result in
            guard let value = result else {
                throw NSError(
                    domain: "Collection.mapConcurrently",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Concurrent map completed without filling all result slots."]
                )
            }
            return value
        }
    }
}
