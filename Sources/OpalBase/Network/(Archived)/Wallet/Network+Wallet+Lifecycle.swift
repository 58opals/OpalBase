// Network+Wallet+Lifecycle.swift

import Foundation

extension Network.Wallet {
    public enum Lifecycle {}
}

extension Network.Wallet.Lifecycle {
    public enum Error: Swift.Error {
        case ownerReleased
        case monitoringAlreadyRunning
        case monitoringFailed(Swift.Error)
        case emptyAccounts
    }
}

extension Network.Wallet.Lifecycle.Error: Equatable {
    public static func == (lhs: Network.Wallet.Lifecycle.Error, rhs: Network.Wallet.Lifecycle.Error) -> Bool {
        switch (lhs, rhs) {
        case (.ownerReleased, .ownerReleased),
            (.monitoringAlreadyRunning, .monitoringAlreadyRunning),
            (.monitoringFailed, .monitoringFailed),
            (.emptyAccounts, .emptyAccounts):
            return true
        default:
            return false
        }
    }
}

extension Wallet {
    public func monitorBalances() async throws -> AsyncThrowingStream<Satoshi, Swift.Error> {
        guard !accounts.isEmpty else { throw Network.Wallet.Lifecycle.Error.emptyAccounts }
        await ensureLifecycleRegistrations()
        
        do {
            return try await balanceLifecycleCoordinator.start()
        } catch let error as Lifecycle.Coordinator<Satoshi>.Error {
            switch error {
            case .alreadyRunning:
                throw Network.Wallet.Lifecycle.Error.monitoringAlreadyRunning
            case .noSources:
                throw Network.Wallet.Lifecycle.Error.emptyAccounts
            case let .sourceFailure(_, underlying):
                if let lifecycleError = underlying as? Network.Wallet.Lifecycle.Error {
                    throw lifecycleError
                }
                throw Network.Wallet.Lifecycle.Error.monitoringFailed(underlying)
            }
        } catch let lifecycleError as Network.Wallet.Lifecycle.Error {
            throw lifecycleError
        } catch {
            throw Network.Wallet.Lifecycle.Error.monitoringFailed(error)
        }
    }
    
    public func suspendBalanceMonitoring() async throws {
        do {
            try await balanceLifecycleCoordinator.suspend()
        } catch let error as Lifecycle.Coordinator<Satoshi>.Error {
            switch error {
            case let .sourceFailure(_, underlying):
                if let lifecycleError = underlying as? Network.Wallet.Lifecycle.Error {
                    throw lifecycleError
                }
                throw Network.Wallet.Lifecycle.Error.monitoringFailed(underlying)
            case .alreadyRunning, .noSources:
                return
            }
        } catch let lifecycleError as Network.Wallet.Lifecycle.Error {
            throw lifecycleError
        } catch {
            throw Network.Wallet.Lifecycle.Error.monitoringFailed(error)
        }
    }
    
    public func resumeBalanceMonitoring() async throws {
        do {
            try await balanceLifecycleCoordinator.resume()
        } catch let error as Lifecycle.Coordinator<Satoshi>.Error {
            switch error {
            case let .sourceFailure(_, underlying):
                if let lifecycleError = underlying as? Network.Wallet.Lifecycle.Error {
                    throw lifecycleError
                }
                throw Network.Wallet.Lifecycle.Error.monitoringFailed(underlying)
            case .alreadyRunning, .noSources:
                return
            }
        } catch let lifecycleError as Network.Wallet.Lifecycle.Error {
            throw lifecycleError
        } catch {
            throw Network.Wallet.Lifecycle.Error.monitoringFailed(error)
        }
    }
    
    public func stopBalanceMonitoring() async {
        await balanceLifecycleCoordinator.shutdown()
    }
}

extension Wallet {
    func ensureLifecycleRegistrations() async {
        for account in accounts where balanceLifecycleRegistrations[account.id] == nil {
            await registerAccountLifecycle(for: account)
        }
    }
    
    func registerAccountLifecycle(for account: Account) async {
        guard balanceLifecycleRegistrations[account.id] == nil else { return }
        
        let registration = await balanceLifecycleCoordinator.register(
            label: "wallet-account-\(account.id.base64EncodedString())",
            hooks: .init(
                start: { [weak self, weak account] in
                    guard let self, let account else { throw Network.Wallet.Lifecycle.Error.ownerReleased }
                    
                    let accountStream: AsyncThrowingStream<Satoshi, Swift.Error>
                    do {
                        accountStream = try await account.monitorBalances()
                    } catch {
                        throw Network.Wallet.Lifecycle.Error.monitoringFailed(error)
                    }
                    
                    return AsyncThrowingStream { continuation in
                        let forwardingTask = Task { [weak self] in
                            guard let self else { return }
                            
                            do {
                                for try await _ in accountStream {
                                    let total = try await self.calculateCachedBalance()
                                    continuation.yield(total)
                                }
                                continuation.finish()
                            } catch {
                                continuation.finish(throwing: Network.Wallet.Lifecycle.Error.monitoringFailed(error))
                            }
                        }
                        
                        continuation.onTermination = { _ in
                            forwardingTask.cancel()
                            Task { await account.stopBalanceMonitoring() }
                        }
                    }
                },
                suspend: { [weak account] in
                    guard let account else { return }
                    try await account.suspendBalanceMonitoring()
                },
                resume: { [weak account] in
                    guard let account else { throw Network.Wallet.Lifecycle.Error.ownerReleased }
                    try await account.resumeBalanceMonitoring()
                },
                shutdown: { [weak account] in
                    guard let account else { return }
                    await account.stopBalanceMonitoring()
                }
            )
        )
        
        balanceLifecycleRegistrations[account.id] = registration
    }
}
