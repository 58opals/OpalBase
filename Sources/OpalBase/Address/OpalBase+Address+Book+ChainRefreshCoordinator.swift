// OpalBase+Address+Book+ChainRefreshCoordinator.swift

import Foundation

extension _OpalBase.Address.Book {
    /// Bounds independent address hydrations and excludes complete account refreshes.
    actor ChainRefreshCoordinator {
        private enum Scope: Equatable {
            case account
            case address(OpalBase.Address)
        }

        private struct Waiter {
            let identifier: UUID
            let scope: Scope
            let continuation: CheckedContinuation<Void, any Swift.Error>
        }

        private let maximumActiveAddresses = 4
        private var isAccountRefreshActive = false
        private var activeAddresses: Set<OpalBase.Address> = []
        private var waiters: [Waiter] = []

        var queuedOperationCount: Int { waiters.count }

        func performExclusively<Result: Sendable>(
            _ operation: @Sendable () async throws -> Result
        ) async throws -> Result {
            try await perform(scope: .account, operation: operation)
        }

        func performForAddress<Result: Sendable>(
            _ address: OpalBase.Address,
            operation: @Sendable () async throws -> Result
        ) async throws -> Result {
            try await perform(scope: .address(address), operation: operation)
        }

        private func perform<Result: Sendable>(
            scope: Scope,
            operation: @Sendable () async throws -> Result
        ) async throws -> Result {
            let identifier = UUID()
            return try await withTaskCancellationHandler {
                try await acquire(identifier: identifier, scope: scope)
                defer { release(scope: scope) }
                try Task.checkCancellation()
                return try await operation()
            } onCancel: {
                Task { await self.cancelWaiter(identifier: identifier) }
            }
        }

        private func acquire(identifier: UUID, scope: Scope) async throws {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(identifier: identifier, scope: scope, continuation: continuation))
                admitWaitingOperations()
            }
        }

        private func cancelWaiter(identifier: UUID) {
            guard let index = waiters.firstIndex(where: { $0.identifier == identifier }) else { return }
            waiters.remove(at: index).continuation.resume(throwing: CancellationError())
            admitWaitingOperations()
        }

        private func release(scope: Scope) {
            switch scope {
            case .account: isAccountRefreshActive = false
            case .address(let address): activeAddresses.remove(address)
            }
            admitWaitingOperations()
        }

        private func admitWaitingOperations() {
            guard !isAccountRefreshActive, !waiters.isEmpty else { return }
            if waiters.first?.scope == .account {
                guard activeAddresses.isEmpty else { return }
                isAccountRefreshActive = true
                waiters.removeFirst().continuation.resume()
                return
            }
            while activeAddresses.count < maximumActiveAddresses {
                // A queued account refresh is a barrier: later addresses cannot starve it.
                // Before that barrier, skip only addresses whose own operation is active.
                let barrier = waiters.firstIndex { $0.scope == .account } ?? waiters.endIndex
                guard let index = waiters[..<barrier].firstIndex(where: {
                    if case .address(let address) = $0.scope { return !activeAddresses.contains(address) }
                    return false
                }) else { return }
                let waiter = waiters.remove(at: index)
                if case .address(let address) = waiter.scope {
                    activeAddresses.insert(address)
                    waiter.continuation.resume()
                }
            }
        }
    }
}
