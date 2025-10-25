// Network+Account+Lifecycle.swift

import Foundation

extension Network.Account {
    public enum Lifecycle {}
}

extension Network.Account.Lifecycle {
    public enum Error: Swift.Error {
        case ownerReleased
        case monitoringAlreadyRunning
        case monitoringFailed(Swift.Error)
        case emptyAddresses
    }
}

extension Network.Account.Lifecycle.Error: Equatable {
    public static func == (lhs: Network.Account.Lifecycle.Error, rhs: Network.Account.Lifecycle.Error) -> Bool {
        switch (lhs, rhs) {
        case (.ownerReleased, .ownerReleased),
            (.monitoringAlreadyRunning, .monitoringAlreadyRunning),
            (.monitoringFailed, .monitoringFailed),
            (.emptyAddresses, .emptyAddresses):
            return true
        default:
            return false
        }
    }
}

extension Account {
    public func monitorBalances() async throws -> AsyncThrowingStream<Satoshi, Swift.Error> {
        do {
            return try await balanceLifecycleCoordinator.start()
        } catch let error as Lifecycle.Coordinator<Satoshi>.Error {
            switch error {
            case .alreadyRunning:
                throw Network.Account.Lifecycle.Error.monitoringAlreadyRunning
            case .noSources:
                throw Network.Account.Lifecycle.Error.emptyAddresses
            case let .sourceFailure(_, underlying):
                if let lifecycleError = underlying as? Network.Account.Lifecycle.Error {
                    throw lifecycleError
                }
                throw Network.Account.Lifecycle.Error.monitoringFailed(underlying)
            }
        } catch let lifecycleError as Network.Account.Lifecycle.Error {
            throw lifecycleError
        } catch {
            throw Network.Account.Lifecycle.Error.monitoringFailed(error)
        }
    }
    
    public func suspendBalanceMonitoring() async throws {
        do {
            try await balanceLifecycleCoordinator.suspend()
        } catch let error as Lifecycle.Coordinator<Satoshi>.Error {
            switch error {
            case let .sourceFailure(_, underlying):
                if let lifecycleError = underlying as? Network.Account.Lifecycle.Error {
                    throw lifecycleError
                }
                throw Network.Account.Lifecycle.Error.monitoringFailed(underlying)
            case .alreadyRunning, .noSources:
                return
            }
        } catch let lifecycleError as Network.Account.Lifecycle.Error {
            throw lifecycleError
        } catch {
            throw Network.Account.Lifecycle.Error.monitoringFailed(error)
        }
    }
    
    public func resumeBalanceMonitoring() async throws {
        do {
            try await balanceLifecycleCoordinator.resume()
        } catch let error as Lifecycle.Coordinator<Satoshi>.Error {
            switch error {
            case let .sourceFailure(_, underlying):
                if let lifecycleError = underlying as? Network.Account.Lifecycle.Error {
                    throw lifecycleError
                }
                throw Network.Account.Lifecycle.Error.monitoringFailed(underlying)
            case .alreadyRunning, .noSources:
                return
            }
        } catch let lifecycleError as Network.Account.Lifecycle.Error {
            throw lifecycleError
        } catch {
            throw Network.Account.Lifecycle.Error.monitoringFailed(error)
        }
    }
    
    public func stopBalanceMonitoring() async {
        await balanceLifecycleCoordinator.shutdown()
    }
}

extension Account {
    static func configureBalanceLifecycle(
        coordinator: Lifecycle.Coordinator<Satoshi>,
        account: Account
    ) async -> UUID {
        await coordinator.register(
            label: "account-\(account.id.base64EncodedString())",
            hooks: .init(
                start: { [weak account] in
                    guard let account else { throw Network.Account.Lifecycle.Error.ownerReleased }
                    return try await account.makeBalanceStream()
                },
                suspend: { [weak account] in
                    guard let account else { return }
                    try await account.suspendBalanceStream()
                },
                resume: { [weak account] in
                    guard let account else { throw Network.Account.Lifecycle.Error.ownerReleased }
                    try await account.resumeBalanceStream()
                },
                shutdown: { [weak account] in
                    guard let account else { return }
                    try await account.shutdownBalanceStream()
                }
            )
        )
    }
}
