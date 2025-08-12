// Wallet+Monitor~SwiftFulcrum.swift

import Foundation

extension Wallet {
    public func monitorBalances() async throws -> AsyncThrowingStream<Satoshi, Swift.Error> {
        guard !accounts.isEmpty else { throw Monitor.Error.emptyAccounts }

        do {
            let streams = try await withThrowingTaskGroup(of: AsyncThrowingStream<Satoshi, Swift.Error>.self) { group in
                for account in accounts {
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
                                let total = try await self.getBalance()
                                continuation.yield(total)
                            }
                        } catch {
                            continuation.finish(throwing: Monitor.Error.monitoringFailed(error))
                        }
                    }
                }

                continuation.onTermination = { _ in
                    Task { await self.stopBalanceMonitoring() }
                }
            }
        } catch {
            throw Monitor.Error.monitoringFailed(error)
        }
    }

    public func stopBalanceMonitoring() async {
        for account in accounts {
            await account.stopBalanceMonitoring()
        }
    }
}
