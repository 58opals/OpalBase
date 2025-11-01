// Address+Book+Entry+Publisher.swift

import Foundation

extension Address.Book.Entry {
    actor Publisher {
        private var continuations: [UUID: AsyncStream<Address.Book.Entry>.Continuation] = .init()
        
        func publish(_ entry: Address.Book.Entry) {
            for continuation in continuations.values {
                continuation.yield(entry)
            }
        }
        
        func observeEntries() -> AsyncStream<Address.Book.Entry> {
            AsyncStream { continuation in
                let identifier = addContinuation(continuation)
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    Task { await self.removeContinuation(identifier) }
                }
            }
        }
        
        private func addContinuation(_ continuation: AsyncStream<Address.Book.Entry>.Continuation) -> UUID {
            let identifier = UUID()
            continuations[identifier] = continuation
            return identifier
        }
        
        private func removeContinuation(_ identifier: UUID) {
            continuations.removeValue(forKey: identifier)
        }
    }
}
