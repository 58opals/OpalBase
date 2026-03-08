// OpalBase+Address+Book+Entry+PublisherActor.swift

import Foundation

extension _OpalBase.Address.Book.Entry {
    actor PublisherActor {
        private var continuations: [UUID: AsyncStream<OpalBase.Address.Book.Entry>.Continuation] = .init()
        
        func publish(_ entry: OpalBase.Address.Book.Entry) {
            for continuation in continuations.values {
                continuation.yield(entry)
            }
        }
        
        func observeEntries() -> AsyncStream<OpalBase.Address.Book.Entry> {
            AsyncStream { continuation in
                let identifier = addContinuation(continuation)
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    Task { await self.removeContinuation(identifier) }
                }
            }
        }
        
        private func addContinuation(_ continuation: AsyncStream<OpalBase.Address.Book.Entry>.Continuation) -> UUID {
            let identifier = UUID()
            continuations[identifier] = continuation
            return identifier
        }
        
        private func removeContinuation(_ identifier: UUID) {
            continuations.removeValue(forKey: identifier)
        }
    }
}
