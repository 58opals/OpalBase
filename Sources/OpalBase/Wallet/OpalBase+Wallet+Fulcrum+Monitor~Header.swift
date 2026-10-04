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
                let generation = await dependencies.eventHub.makeMutationPermit()
                do {
                    let stream = try await reader.subscribeToTip()
                    await startupGate?.complete()
                    do {
                        try await consumeHeaderStream(stream, dependencies: dependencies, mutationPermit: generation)
                    } catch {
                        if error.isCancellationError { return }
                        guard !Task.isCancelled else { return }
                        try? await Task.sleep(for: retryDelay)
                        continue
                    }
                    guard !Task.isCancelled else { return }
                    await dependencies.eventHub.publishFailure(.init(address: nil, message: "Block-header subscription ended."), mutationPermit: generation)
                    try? await Task.sleep(for: retryDelay)
                } catch {
                    await startupGate?.complete()
                    if error.isCancellationError { return }
                    await publishFailure(address: nil, error: error, eventHub: dependencies.eventHub, mutationPermit: generation)
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                }
            }

            await startupGate?.complete()
        }
    }

    static func consumeHeaderStream(_ stream: AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error>,
                                    dependencies: WorkerDependencies,
                                    mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) async throws {
        let generation: OpalBase.Network.ChainRefreshMutationPermit
        if let mutationPermit { generation = mutationPermit } else { generation = await dependencies.eventHub.makeMutationPermit() }
        do {
            for try await _ in stream {
                try Task.checkCancellation()
                await handleHeaderSnapshot(dependencies: dependencies)
            }
        } catch {
            if error.isCancellationError {
                throw error
            }
            await publishFailure(address: nil, error: error, eventHub: dependencies.eventHub, mutationPermit: generation)
            throw error
        }
    }

    static func handleHeaderSnapshot(dependencies: WorkerDependencies) async {
        let generation = await dependencies.eventHub.makeMutationPermit()
        do {
            let changeSet = try await dependencies.account.refreshMonitoringTransactionConfirmations(using: dependencies.transactionClient,
                                                                                                      mutationPermit: generation)
            if !changeSet.isEmpty {
                await dependencies.eventHub.publish(.confirmationsChanged(changeSet), mutationPermit: generation)
            }
            await dependencies.eventHub.markHeaderSynchronized(mutationPermit: generation)
        } catch {
            if error.isCancellationError { return }
            await publishFailure(address: nil, error: error, eventHub: dependencies.eventHub, mutationPermit: generation)
        }
    }
}
