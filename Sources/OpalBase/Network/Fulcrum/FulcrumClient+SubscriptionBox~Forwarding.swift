// FulcrumClient+SubscriptionBox~Forwarding.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSubscriptionBox {
    func startForwarding(with updates: AsyncThrowingStream<Notification, Swift.Error>) {
        forwardingTask?.cancel()
        forwardingGeneration &+= 1
        let generation = forwardingGeneration
        forwardingTask = Task {
            await self.forward(updates: updates, generation: generation)
        }
    }

    func forward(updates: AsyncThrowingStream<Notification, Swift.Error>, generation: UInt64) async {
        do {
            for try await update in updates {
                continuation.yield(update)
            }

            if await evaluateTerminationDeferralForRecovery() { return }

            await finishStream(for: generation)
        } catch is CancellationError {
            if await evaluateTerminationDeferralForRecovery() { return }

            await finishStream(for: generation)
        } catch {
            if checkClientCancellation(error) {
                if await evaluateTerminationDeferralForRecovery() { return }

                await finishStream(for: generation)
                return
            }
            if checkTerminationErrorSuppression(error) { return }
            if isExpectingResubscribe && checkRecoverability(error) { return }
            if await evaluateTerminationDeferralForRecovery() { return }

            await finishStream(for: generation, with: error)
        }
    }

    func finishStream(for generation: UInt64, with error: Swift.Error? = nil) async {
        guard generation == forwardingGeneration else { return }
        guard !isTerminated else { return }
        isTerminated = true
        requestForwardingStop()
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
        await tearDownCurrentHandler()
        await notifyTermination()
    }

    func notifyTermination() async {
        guard !hasNotifiedTermination else { return }
        hasNotifiedTermination = true
        await onTermination(id)
    }

    func requestForwardingStop() {
        forwardingTask?.cancel()
        forwardingTask = nil
    }

    func stopForwardingAndWait() async {
        forwardingTask?.cancel()
        await forwardingTask?.value
        forwardingTask = nil
    }

    func waitForForwardingCompletion() async {
        guard let forwardingTask else { return }
        await forwardingTask.value
        self.forwardingTask = nil
    }

    func tearDownCurrentHandler() async {
        guard let handler = cancellationHandler else { return }
        cancellationHandler = nil
        await handler()
    }
}
