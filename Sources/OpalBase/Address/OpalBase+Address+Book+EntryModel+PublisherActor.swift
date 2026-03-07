// OpalBase.Address+BookActor+EntryModel+PublisherActor.swift

import Foundation

extension _OpalBase.Address.Book.EntryModel {
    actor PublisherActor {
        private var continuations: [UUID: AsyncStream<OpalBase.Address.Book.EntryModel>.Continuation] = .init()
        
        func publish(_ entry: OpalBase.Address.Book.EntryModel) {
            for continuation in continuations.values {
                continuation.yield(entry)
            }
        }
        
        func observeEntries() -> AsyncStream<OpalBase.Address.Book.EntryModel> {
            AsyncStream { continuation in
                let identifier = addContinuation(continuation)
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    Task { await self.removeContinuation(identifier) }
                }
            }
        }
        
        private func addContinuation(_ continuation: AsyncStream<OpalBase.Address.Book.EntryModel>.Continuation) -> UUID {
            let identifier = UUID()
            continuations[identifier] = continuation
            return identifier
        }
        
        private func removeContinuation(_ identifier: UUID) {
            continuations.removeValue(forKey: identifier)
        }
    }
}
