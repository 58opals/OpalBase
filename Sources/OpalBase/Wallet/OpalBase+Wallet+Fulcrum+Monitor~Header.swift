// OpalBase+Wallet+Fulcrum+Monitor~Header.swift

import Foundation

extension _OpalBase.Wallet.Fulcrum.Monitor {
    func startHeaderSubscription() async {
        guard headerTask == nil else { return }
        headerTask = Self.makeHeaderTask(dependencies: dependencies)
    }
}

extension _OpalBase.Wallet.Fulcrum.Monitor {
    static func makeHeaderTask(dependencies: WorkerDependencies) -> Task<Void, Never> {
        let reader = dependencies.blockHeaderReader
        let retryDelay = dependencies.retryDelay

        return Task.detached {
            while !Task.isCancelled {
                do {
                    let stream = try await reader.subscribeToTip()
                    try await consumeHeaderStream(stream, dependencies: dependencies)
                } catch {
                    if error.isCancellationError { return }
                    publishFailure(address: nil, error: error, relay: dependencies.relay)
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                }
            }
        }
    }

    static func consumeHeaderStream(_ stream: AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error>,
                                    dependencies: WorkerDependencies) async throws {
        do {
            for try await _ in stream {
                try Task.checkCancellation()
                await handleHeaderSnapshot(dependencies: dependencies)
            }
        } catch {
            if error.isCancellationError {
                throw error
            }
            publishFailure(address: nil, error: error, relay: dependencies.relay)
            throw error
        }
    }

    static func handleHeaderSnapshot(dependencies: WorkerDependencies) async {
        do {
            let changeSet = try await dependencies.account.refreshTransactionConfirmations(using: dependencies.transactionClient)
            if !changeSet.isEmpty {
                dependencies.relay.publish(.confirmationsChanged(changeSet))
            }
        } catch {
            publishFailure(address: nil, error: error, relay: dependencies.relay)
        }
    }
}
