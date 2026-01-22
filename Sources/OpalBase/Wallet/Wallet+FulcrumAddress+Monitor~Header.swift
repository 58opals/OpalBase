// Wallet+FulcrumAddress+Monitor~Header.swift

import Foundation

extension Wallet.FulcrumAddress.Monitor {
    func startHeaderSubscription() async {
        guard headerTask == nil else { return }
        let reader = blockHeaderReader
        let retryDelay = self.retryDelay
        headerTask = Task {
            while !Task.isCancelled {
                do {
                    let stream = try await reader.subscribeToTip()
                    try await consumeHeaderStream(stream)
                } catch {
                    if error.checkCancellation { return }
                    await publishFailure(address: nil, error: error)
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                }
            }
        }
    }
    
    private func consumeHeaderStream(_ stream: AsyncThrowingStream<Network.BlockHeaderSnapshot, any Swift.Error>) async throws {
        do {
            for try await snapshot in stream {
                try Task.checkCancellation()
                await handleHeaderSnapshot(snapshot)
            }
        } catch {
            if error.checkCancellation {
                throw error
            }
            await publishFailure(address: nil, error: error)
            throw error
        }
    }
    
    private func handleHeaderSnapshot(_ snapshot: Network.BlockHeaderSnapshot) async {
        do {
            let changeSet = try await account.refreshTransactionConfirmations(using: transactionHandler)
            if !changeSet.isEmpty {
                publish(.confirmationsChanged(changeSet))
            }
        } catch {
            await publishFailure(address: nil, error: error)
        }
    }
}
