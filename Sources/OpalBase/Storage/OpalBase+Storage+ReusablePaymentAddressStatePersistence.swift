// OpalBase+Storage+ReusablePaymentAddressStatePersistence.swift

import Foundation

extension _OpalBase.Storage {
    /// Makes generation-staged durable state operations for one Cash Code
    /// registration. The identifier is hashed before it is used in backend
    /// keys.
    public func makeReusablePaymentAddressStatePersistence(
        identifier: Data
    ) -> OpalBase.ReusablePaymentAddress.StatePersistence {
        let identifierHash = OpalCryptoAdapter.sha256(identifier)
            .hexadecimalString
        return .init(
            loadState: {
                try await self.loadReusablePaymentAddressState(
                    identifierHash: identifierHash
                )
            },
            saveState: { state, expectedRevision in
                try await self.saveReusablePaymentAddressState(
                    state,
                    replacingRevision: expectedRevision,
                    identifierHash: identifierHash
                )
            }
        )
    }

    private func loadReusablePaymentAddressState(
        identifierHash: String
    ) async throws -> OpalBase.ReusablePaymentAddress.RestorationState? {
        try await PersistenceOperationCoordinator.processWideCoordinator
            .performExclusively {
                try await self.loadReusablePaymentAddressStateAssumingExclusiveAccess(
                    identifierHash: identifierHash
                )?.state
            }
    }

    private func saveReusablePaymentAddressState(
        _ state: OpalBase.ReusablePaymentAddress.RestorationState,
        replacingRevision expectedRevision: UInt64?,
        identifierHash: String
    ) async throws {
        try await PersistenceOperationCoordinator.processWideCoordinator
            .performExclusively {
                try state.validate()
                let current = try await self
                    .loadReusablePaymentAddressStateAssumingExclusiveAccess(
                        identifierHash: identifierHash
                    )
                guard current?.state.revision == expectedRevision else {
                    throw OpalBase.ReusablePaymentAddress.Error
                        .stateRevisionConflict
                }
                let requiredRevision: UInt64
                if let expectedRevision {
                    let (incremented, overflow) = expectedRevision
                        .addingReportingOverflow(1)
                    guard !overflow else {
                        throw OpalBase.ReusablePaymentAddress.Error
                            .stateRevisionConflict
                    }
                    requiredRevision = incremented
                } else {
                    requiredRevision = 1
                }
                guard state.revision == requiredRevision else {
                    throw OpalBase.ReusablePaymentAddress.Error
                        .stateRevisionConflict
                }

                let generation = UUID().uuidString.lowercased()
                let stagedKey = Self.makeReusablePaymentAddressStateKey(
                    identifierHash: identifierHash,
                    generation: generation
                )
                let committedKey = Self
                    .makeReusablePaymentAddressCommittedGenerationKey(
                        identifierHash: identifierHash
                    )
                let encoded = try await self.encodeSnapshot(state)
                do {
                    try await self.storeValue(encoded, for: stagedKey)
                    try await self.storeValue(
                        Data(generation.utf8),
                        for: committedKey
                    )
                } catch {
                    let saveError = error
                    let canRemoveStagedState = await self
                        .restoreReusablePaymentAddressCommittedGenerationIfNeeded(
                            stagedGeneration: generation,
                            previousCommittedGeneration: current?.generation,
                            identifierHash: identifierHash
                        )
                    if canRemoveStagedState {
                        try? await self.removeValue(for: stagedKey)
                    }
                    throw saveError
                }

                if let priorGeneration = current?.generation,
                   priorGeneration != generation {
                    try? await self.removeValue(
                        for: Self.makeReusablePaymentAddressStateKey(
                            identifierHash: identifierHash,
                            generation: priorGeneration
                        )
                    )
                }
            }
    }

    private func loadReusablePaymentAddressStateAssumingExclusiveAccess(
        identifierHash: String
    ) async throws -> (
        generation: String,
        state: OpalBase.ReusablePaymentAddress.RestorationState
    )? {
        guard let generation = try await
            loadReusablePaymentAddressCommittedGeneration(
                identifierHash: identifierHash
            ) else { return nil }
        let stateKey = Self.makeReusablePaymentAddressStateKey(
            identifierHash: identifierHash,
            generation: generation
        )
        guard let stateData = try await loadValue(for: stateKey) else {
            throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
        }
        let state: OpalBase.ReusablePaymentAddress.RestorationState
        do {
            state = try decodeSnapshot(
                OpalBase.ReusablePaymentAddress.RestorationState.self,
                from: stateData
            )
        } catch {
            throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
        }
        try state.validate()
        return (generation, state)
    }

    private func loadReusablePaymentAddressCommittedGeneration(
        identifierHash: String
    ) async throws -> String? {
        let committedKey = Self
            .makeReusablePaymentAddressCommittedGenerationKey(
                identifierHash: identifierHash
            )
        guard let generationData = try await loadValue(for: committedKey)
        else {
            return nil
        }
        guard let generation = String(
            data: generationData,
            encoding: .utf8
        ),
        !generation.isEmpty else {
            throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
        }
        return generation
    }

    private func restoreReusablePaymentAddressCommittedGenerationIfNeeded(
        stagedGeneration: String,
        previousCommittedGeneration: String?,
        identifierHash: String
    ) async -> Bool {
        let committedGeneration: String?
        do {
            committedGeneration = try await
                loadReusablePaymentAddressCommittedGeneration(
                    identifierHash: identifierHash
                )
        } catch {
            return false
        }

        guard committedGeneration == stagedGeneration else {
            return true
        }

        let committedKey = Self
            .makeReusablePaymentAddressCommittedGenerationKey(
                identifierHash: identifierHash
            )
        if let previousCommittedGeneration {
            try? await storeValue(
                Data(previousCommittedGeneration.utf8),
                for: committedKey
            )
        } else {
            try? await removeValue(for: committedKey)
        }

        do {
            return try await loadReusablePaymentAddressCommittedGeneration(
                identifierHash: identifierHash
            ) != stagedGeneration
        } catch {
            return false
        }
    }

    private static func makeReusablePaymentAddressCommittedGenerationKey(
        identifierHash: String
    ) -> OpalBase.Storage.Key {
        .custom("cash-code.state.\(identifierHash).committed")
    }

    private static func makeReusablePaymentAddressStateKey(
        identifierHash: String,
        generation: String
    ) -> OpalBase.Storage.Key {
        .custom("cash-code.state.\(identifierHash).\(generation)")
    }
}
