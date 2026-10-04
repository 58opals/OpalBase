// OpalBase+Wallet+Fulcrum+Monitor~Observation.swift

import Foundation

extension _OpalBase.Wallet.Fulcrum.Monitor {
    /// Account readiness is independent of address registration and retained chain data.
    public enum State: Sendable {
        case synchronizing
        case synchronized
        case failed(Failure)
    }

    /// Ordered data and readiness observations. Existing Event streams keep their API.
    public enum Observation: Sendable {
        case event(Event)
        case state(State)
    }

    public func makeObservationStream(autoStart: Bool = true) async -> AsyncThrowingStream<Observation, Swift.Error> {
        guard !isFinished else {
            return AsyncThrowingStream { $0.finish() }
        }
        let identifier = UUID()
        activeEventStreamIdentifiers.insert(identifier)
        return await eventHub.makeObservationStream(identifier: identifier, autoStart: autoStart, monitor: self)
    }

    func startConnectionObservation() async {
        guard let connectionRecoveryStates, connectionTask == nil else { return }
        let eventHub = eventHub
        connectionTask = Task {
            for await state in connectionRecoveryStates {
                guard !Task.isCancelled else { return }
                await eventHub.updateConnectionRecovery(state)
            }

        }
    }
}

extension _OpalBase.Wallet.Fulcrum.Monitor {
    actor EventHub {
        typealias Event = OpalBase.Wallet.Fulcrum.Monitor.Event
        typealias Continuation = AsyncThrowingStream<Event, Swift.Error>.Continuation
        typealias ObservationContinuation = AsyncThrowingStream<Observation, Swift.Error>.Continuation

        private struct AddressProgress {
            var isSubscribed = false
            var activeSubscriptionIdentifier: UUID?
            var isSynchronized = false
            var failure: Failure?
        }
        private var continuations: [UUID: Continuation] = .init()
        private var observationContinuations: [UUID: ObservationContinuation] = .init()
        private var progressByAddress: [OpalBase.Address: AddressProgress] = .init()
        private var isScopeEstablished = false
        private var connectionState: OpalBase.Network.Fulcrum.Client.ConnectionRecoveryObservation.State = .ready
        private var producerGeneration: UInt64?
        private var producerSequence: UInt64?
        private let generation = OpalBase.Network.ChainRefreshGeneration()
        private var fullRefresh: (id: UUID, task: Task<Void, Swift.Error>)?
        private var monitorFailure: Failure?
        private var lastStateKey: String? = "synchronizing"
        private var isFinished = false
        private let tracksConnectionRecovery: Bool
        init(tracksConnectionRecovery: Bool = false) { self.tracksConnectionRecovery = tracksConnectionRecovery }

        func makeStream(identifier: UUID, autoStart: Bool, monitor: OpalBase.Wallet.Fulcrum.Monitor) -> AsyncThrowingStream<Event, Swift.Error> {
            AsyncThrowingStream { continuation in
                guard !isFinished else { continuation.finish(); return }
                continuations[identifier] = continuation
                if autoStart {
                    Task(priority: .userInitiated) { await monitor.startIfStreamIsStillActive(identifier: identifier) }
                }
                continuation.onTermination = { [monitor] termination in
                    Task {
                        switch termination {
                        case .cancelled: await monitor.handleEventStreamTermination(identifier: identifier, reason: .cancelled)
                        default: await monitor.handleEventStreamTermination(identifier: identifier, reason: .stopped)
                        }
                    }
                }
            }
        }

        func makeObservationStream(identifier: UUID, autoStart: Bool, monitor: OpalBase.Wallet.Fulcrum.Monitor) -> AsyncThrowingStream<Observation, Swift.Error> {
            AsyncThrowingStream { continuation in
                guard !isFinished else { continuation.finish(); return }
                observationContinuations[identifier] = continuation
                continuation.yield(.state(currentState))
                if autoStart {
                    Task(priority: .userInitiated) { await monitor.startIfStreamIsStillActive(identifier: identifier) }
                }
                continuation.onTermination = { [monitor] termination in
                    Task {
                        switch termination {
                        case .cancelled: await monitor.handleEventStreamTermination(identifier: identifier, reason: .cancelled)
                        default: await monitor.handleEventStreamTermination(identifier: identifier, reason: .stopped)
                        }
                    }
                }
            }
        }

        func removeContinuation(withIdentifier identifier: UUID) {
            continuations.removeValue(forKey: identifier)
            observationContinuations.removeValue(forKey: identifier)
        }

        func publish(_ event: Event, mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil,
                     activeSubscription: (address: OpalBase.Address, identifier: UUID)? = nil) {
            guard !isFinished else { return }
            if let mutationPermit {
                guard isCurrent(mutationPermit), !Task.isCancelled else { return }
            }
            if let activeSubscription {
                guard isActiveSubscription(for: activeSubscription.address, identifier: activeSubscription.identifier) else { return }
            }
            for continuation in continuations.values { continuation.yield(event) }
            for continuation in observationContinuations.values { continuation.yield(.event(event)) }
        }

        func registerAddress(_ address: OpalBase.Address) {
            guard !isFinished, progressByAddress[address] == nil else { return }
            progressByAddress[address] = AddressProgress()
            publishStateIfChanged()
        }

        func establishScope() {
            isScopeEstablished = true
            publishStateIfChanged()
        }

        func markSubscriptionReady(for address: OpalBase.Address, identifier: UUID) {
            guard !isFinished else { return }
            if progressByAddress[address]?.isSubscribed != true {
                progressByAddress[address, default: AddressProgress()].isSynchronized = false
            }
            progressByAddress[address, default: AddressProgress()].isSubscribed = true
            progressByAddress[address, default: AddressProgress()].activeSubscriptionIdentifier = identifier
            publishStateIfChanged()
        }

        func isActiveSubscription(for address: OpalBase.Address, identifier: UUID) -> Bool {
            !isFinished && progressByAddress[address]?.activeSubscriptionIdentifier == identifier
        }

        func markSubscriptionEnded(for address: OpalBase.Address, identifier: UUID? = nil) {
            guard !isFinished else { return }
            if let identifier, !isActiveSubscription(for: address, identifier: identifier) { return }
            progressByAddress[address, default: AddressProgress()].activeSubscriptionIdentifier = nil
            progressByAddress[address, default: AddressProgress()].isSubscribed = false
            progressByAddress[address, default: AddressProgress()].isSynchronized = false
            progressByAddress[address, default: AddressProgress()].failure = .init(address: address, message: "Address subscription ended.")
            publishStateIfChanged()
        }

        /// Producer validation and permit capture must not suspend between these operations.
        func prepareAddressUpdate(for address: OpalBase.Address, subscriptionIdentifier: UUID, producerGeneration: UInt64?,
            matchingSuccessfulPermit: OpalBase.Network.ChainRefreshMutationPermit?) -> OpalBase.Network.ChainRefreshMutationPermit? {
            guard isActiveSubscription(for: address, identifier: subscriptionIdentifier) else { return nil }
            guard adoptSubscriptionGeneration(producerGeneration) else { return nil }
            if let matchingSuccessfulPermit, isCurrent(matchingSuccessfulPermit) { return nil }
            progressByAddress[address, default: AddressProgress()].isSubscribed = true
            return beginAddressUpdate(for: address)
        }

        func beginAddressUpdate(for address: OpalBase.Address) -> OpalBase.Network.ChainRefreshMutationPermit {
            progressByAddress[address, default: AddressProgress()].isSynchronized = false
            publishStateIfChanged()
            return generation.makePermit()
        }

        func makeMutationPermit() -> OpalBase.Network.ChainRefreshMutationPermit { generation.makePermit() }

        func isCurrent(_ updateGeneration: OpalBase.Network.ChainRefreshMutationPermit) -> Bool {
            !isFinished && updateGeneration.isCurrent
        }

        func markAddressSynchronized(_ address: OpalBase.Address, generation updateGeneration: OpalBase.Network.ChainRefreshMutationPermit,
                                     subscriptionIdentifier: UUID? = nil) {
            guard isCurrent(updateGeneration), progressByAddress[address]?.isSubscribed == true else { return }
            if let subscriptionIdentifier, !isActiveSubscription(for: address, identifier: subscriptionIdentifier) { return }
            progressByAddress[address, default: AddressProgress()].isSynchronized = true
            progressByAddress[address, default: AddressProgress()].failure = nil
            publishStateIfChanged()
        }

        /// Simultaneous address failures join one complete account fallback in the current connection generation.
        func performFullRefresh(
            generation updateGeneration: OpalBase.Network.ChainRefreshMutationPermit,
            operation: @escaping @Sendable () async throws -> Void
        ) async throws {
            guard isCurrent(updateGeneration), !Task.isCancelled else { throw CancellationError() }
            if let fullRefresh { return try await fullRefresh.task.value }
            let id = UUID()
            let task = Task {
                try await operation()
                try Task.checkCancellation()
                guard self.isCurrent(updateGeneration) else { throw CancellationError() }
            }
            fullRefresh = (id, task)
            do {
                try await task.value
                if fullRefresh?.id == id { fullRefresh = nil }
            } catch {
                if fullRefresh?.id == id { fullRefresh = nil }
                throw error
            }
        }

        func publishFailure(_ failure: Failure, mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) {
            guard !isFinished else { return }
            if let mutationPermit {
                guard isCurrent(mutationPermit), !Task.isCancelled else { return }
            }
            publish(.encounteredFailure(failure), mutationPermit: mutationPermit)
            if let address = failure.address {
                progressByAddress[address, default: AddressProgress()].failure = failure
                progressByAddress[address, default: AddressProgress()].isSynchronized = false
            } else {
                monitorFailure = failure
            }
            publishStateIfChanged()
        }

        func markHeaderSynchronized(mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) {
            guard !isFinished else { return }
            if let mutationPermit {
                guard isCurrent(mutationPermit), !Task.isCancelled else { return }
            }
            monitorFailure = nil
            publishStateIfChanged()
        }

        /// Both data and phase streams can introduce a generation. Adoption invalidates once.
        func adoptSubscriptionGeneration(_ producerGeneration: UInt64?) -> Bool {
            guard !isFinished else { return false }
            guard let producerGeneration else { return true }
            if let current = self.producerGeneration, producerGeneration < current { return false }
            guard self.producerGeneration != producerGeneration else { return true }
            self.producerGeneration = producerGeneration
            generation.invalidate()
            fullRefresh?.task.cancel()
            fullRefresh = nil
            if tracksConnectionRecovery { connectionState = .recovering }
            for address in progressByAddress.keys {
                progressByAddress[address]?.isSynchronized = false
                progressByAddress[address]?.isSubscribed = false
            }
            publishStateIfChanged()
            return true
        }

        func updateConnectionRecovery(_ observation: OpalBase.Network.Fulcrum.Client.ConnectionRecoveryObservation) {
            guard !isFinished else { return }
            if let sequence = producerSequence, observation.sequence <= sequence { return }
            guard adoptSubscriptionGeneration(observation.generation) else { return }
            producerSequence = observation.sequence
            // Same-generation delayed outage phases never invalidate newly hydrated data.
            connectionState = observation.state
            publishStateIfChanged()
        }

        private var currentState: State {
            if let monitorFailure { return .failed(monitorFailure) }
            if let address = progressByAddress.keys.sorted(by: { $0.string < $1.string }).first(where: { progressByAddress[$0]?.failure != nil }),
               let failure = progressByAddress[address]?.failure {
                return .failed(failure)
            }
            guard isScopeEstablished, connectionState == .ready,
                  progressByAddress.values.allSatisfy({ $0.isSubscribed && $0.isSynchronized }) else {
                return .synchronizing
            }
            return .synchronized
        }

        private func publishStateIfChanged() {
            guard !isFinished else { return }
            let state = currentState
            let key: String
            switch state {
            case .synchronizing: key = "synchronizing"
            case .synchronized: key = "synchronized"
            case .failed(let failure): key = "failed:\(failure.address?.string ?? ""):\(failure.message)"
            }
            guard key != lastStateKey else { return }
            lastStateKey = key
            for continuation in observationContinuations.values { continuation.yield(.state(state)) }
        }

        func finishAll() {
            isFinished = true
            generation.finish()
            fullRefresh?.task.cancel()
            fullRefresh = nil
            let activeContinuations = Array(continuations.values)
            let activeObservationContinuations = Array(observationContinuations.values)
            continuations.removeAll()
            observationContinuations.removeAll()
            for continuation in activeContinuations { continuation.finish() }
            for continuation in activeObservationContinuations { continuation.finish() }
        }
    }
}
