// OpalBase+Wallet+Fulcrum+Monitor~Header.swift

import Foundation

extension _OpalBase.Wallet.Fulcrum.Monitor {
    func startHeaderSubscription() async {
        guard headerTask == nil else { return }

        let startupGate = StartupGate()
        headerTask = Self.makeHeaderTask(dependencies: dependencies, startupGate: startupGate)
        await startupGate.wait()
    }
}

extension _OpalBase.Wallet.Fulcrum.Monitor {
    static func makeHeaderTask(dependencies: WorkerDependencies,
                               startupGate: StartupGate? = nil) -> Task<Void, Never> {
        let reader = dependencies.blockHeaderReader
        let retryDelay = dependencies.retryDelay

        return Task {
            while !Task.isCancelled {
                do {
                    let stream = try await reader.subscribeToTip()
                    await startupGate?.complete()
                    do {
                        try await consumeHeaderStream(stream, dependencies: dependencies)
                    } catch {
                        if error.isCancellationError { return }
                        guard !Task.isCancelled else { return }
                        try? await Task.sleep(for: retryDelay)
                        continue
                    }
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                } catch {
                    await startupGate?.complete()
                    if error.isCancellationError { return }
                    await publishFailure(address: nil, error: error, eventHub: dependencies.eventHub)
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                }
            }

            await startupGate?.complete()
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
            await publishFailure(address: nil, error: error, eventHub: dependencies.eventHub)
            throw error
        }
    }

    static func handleHeaderSnapshot(dependencies: WorkerDependencies) async {
        do {
            let changeSet = try await dependencies.account.refreshTransactionConfirmations(using: dependencies.transactionClient)
            if !changeSet.isEmpty {
                await dependencies.eventHub.publish(.confirmationsChanged(changeSet))
            }
        } catch {
            await publishFailure(address: nil, error: error, eventHub: dependencies.eventHub)
        }
    }
}
