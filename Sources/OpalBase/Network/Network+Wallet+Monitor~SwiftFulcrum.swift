// Network+Wallet+Monitor~SwiftFulcrum.swift

import Foundation

extension Network.Wallet.Monitor {
    public func monitorBalances() async throws -> AsyncThrowingStream<Satoshi, Swift.Error> {
        guard await !wallet.accounts.isEmpty else { throw Network.Wallet.Monitor.Error.emptyAccounts }

        do {
            let streams = try await withThrowingTaskGroup(of: AsyncThrowingStream<Satoshi, Swift.Error>.self) { group in
                for account in await wallet.accounts {
                    group.addTask {
                        try await account.monitorBalances()
                    }
                }

                var collected: [AsyncThrowingStream<Satoshi, Swift.Error>] = []
                for try await stream in group { collected.append(stream) }
                return collected
            }

            return AsyncThrowingStream { continuation in
                for stream in streams {
                    Task {
                        do {
                            for try await _ in stream {
                                let total = try await wallet.getBalance()
                                continuation.yield(total)
                            }
                        } catch {
                            continuation.finish(throwing: Network.Wallet.Monitor.Error.monitoringFailed(error))
                        }
                    }
                }

                continuation.onTermination = { _ in
                    Task { await self.stopBalanceMonitoring() }
                }
            }
        } catch {
            throw Network.Wallet.Monitor.Error.monitoringFailed(error)
        }
    }

    public func stopBalanceMonitoring() async {
        for account in await wallet.accounts {
            await account.stopBalanceMonitoring()
        }
    }
}
