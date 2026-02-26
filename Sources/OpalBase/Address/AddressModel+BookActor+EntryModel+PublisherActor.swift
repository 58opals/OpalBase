// AddressModel+BookActor+EntryModel+PublisherActor.swift

import Foundation

extension AddressModel.BookActor.EntryModel {
    actor PublisherActor {
        private var continuations: [UUID: AsyncStream<AddressModel.BookActor.EntryModel>.Continuation] = .init()
        
        func publish(_ entry: AddressModel.BookActor.EntryModel) {
            for continuation in continuations.values {
                continuation.yield(entry)
            }
        }
        
        func observeEntries() -> AsyncStream<AddressModel.BookActor.EntryModel> {
            AsyncStream { continuation in
                let identifier = addContinuation(continuation)
                continuation.onTermination = { [weak self] _ in
                    guard let self else { return }
                    Task { await self.removeContinuation(identifier) }
                }
            }
        }
        
        private func addContinuation(_ continuation: AsyncStream<AddressModel.BookActor.EntryModel>.Continuation) -> UUID {
            let identifier = UUID()
            continuations[identifier] = continuation
            return identifier
        }
        
        private func removeContinuation(_ identifier: UUID) {
            continuations.removeValue(forKey: identifier)
        }
    }
}
