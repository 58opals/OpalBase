// OpalBase+Account+MosaicPrivateAlphaRuntime+Creation.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Persists the exact cross-package binding before returning a live wallet host.
    static func createFreshHost(
        account: OpalBase.Account,
        fusionAttempt: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .FreshAttempt,
        walletReservationIdentifier: UUID,
        walletGeneration: UInt64,
        profile: OpalFusion.Mosaic.Profile,
        network: OpalBase.Network.Environment,
        selectedInputs: [OpalBase.Transaction.Output.Unspent],
        outputAmountsSatoshis: [UInt64],
        transactionReader: OpalBase.Network.TransactionReader,
        journalAttempt: consuming OpalBase.Account
            .MosaicPrivateAlphaJournal.FreshAttempt
    ) async throws -> FreshHost {
        guard profile == .opalMainnetAlpha,
              network == .mainnet else {
            throw Failure.invalidNetworkBinding
        }
        let binding = fusionAttempt.binding
        let privateDeploymentOwner: OpalFusion.MosaicPrivateAlphaRuntime.Owner
        do {
            privateDeploymentOwner = try .init(claiming: fusionAttempt)
        } catch {
            throw Failure(error)
        }
        return try await createFreshHost(
            account: account,
            binding: binding,
            privateDeploymentOwner: privateDeploymentOwner,
            walletReservationIdentifier: walletReservationIdentifier,
            walletGeneration: walletGeneration,
            profile: profile,
            network: network,
            selectedInputs: selectedInputs,
            outputAmountsSatoshis: outputAmountsSatoshis,
            transactionReader: transactionReader,
            journalAttempt: journalAttempt
        )
    }

    private static func createFreshHost(
        account: OpalBase.Account,
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
        privateDeploymentOwner: OpalFusion.MosaicPrivateAlphaRuntime.Owner,
        walletReservationIdentifier: UUID,
        walletGeneration: UInt64,
        profile: OpalFusion.Mosaic.Profile,
        network: OpalBase.Network.Environment,
        selectedInputs: [OpalBase.Transaction.Output.Unspent],
        outputAmountsSatoshis: [UInt64],
        transactionReader: OpalBase.Network.TransactionReader,
        journalAttempt: consuming OpalBase.Account
            .MosaicPrivateAlphaJournal.FreshAttempt
    ) async throws -> FreshHost {
        guard let attemptBinding = OpalBase.Account.MosaicAttemptBinding(
            attemptIdentifier: binding.attemptIdentifier,
            generationIdentifier: binding.generationIdentifier,
            materialIdentifier: binding.materialIdentifier,
            walletReservationReference: .init(
                identifier: walletReservationIdentifier,
                generation: walletGeneration
            )
        ) else {
            throw Failure.invalidBinding
        }
        do {
            let freshAttempt = journalAttempt.claimAttempt()
            return .init(
                binding: .init(binding),
                privateDeploymentOwner: privateDeploymentOwner,
                transactionHost: try await account.makeMosaicTransactionHost(
                    profile: profile,
                    network: network,
                    attemptBinding: attemptBinding,
                    selectedInputs: selectedInputs,
                    outputAmountsSatoshis: outputAmountsSatoshis,
                    transactionReader: transactionReader,
                    freshAttempt: freshAttempt
                ),
                previousOutputSource: transactionReader
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw Failure(error)
        }
    }

    /// Persists and reads back the initial Fusion recovery snapshot before the wallet journal binding,
    /// then creates the exact private-alpha host without exposing OpalFusion to the app target.
    @_spi(MosaicPrivateAlpha)
    public static func createFreshApplicationHost(
        account: OpalBase.Account,
        binding: Binding,
        discoveryEpochStartUnixSeconds: UInt64,
        walletReservationIdentifier: UUID,
        walletGeneration: UInt64,
        selectedInputs: [OpalBase.Transaction.Output.Unspent],
        outputAmountsSatoshis: [UInt64],
        transactionReader: OpalBase.Network.TransactionReader,
        recoveryPersistence: FusionRecoveryPersistence,
        journalAttempt: consuming OpalBase.Account
            .MosaicPrivateAlphaJournal.FreshAttempt
    ) async throws -> FreshHost {
        do {
            let fusionAttempt = try OpalFusion.MosaicPrivateAlphaRuntime
                .createFreshAttempt(
                    boundTo: binding.fusionBinding,
                    discoveryEpochStartUnixSeconds:
                        discoveryEpochStartUnixSeconds
                )
            let fusionBinding = fusionAttempt.binding
            let privateDeploymentOwner = try OpalFusion
                .MosaicPrivateAlphaRuntime.Owner(claiming: fusionAttempt)
            let initialStep = try await privateDeploymentOwner.nextStep()
            guard case let .persist(initialTransition) = initialStep,
                  initialTransition.expectedSnapshot == nil,
                  Binding(initialTransition.binding) == binding else {
                throw Failure.invalidRecoveryState
            }
            let exactReadback = try await recoveryPersistence.persist(
                .init(initialTransition)
            )
            let acknowledged = try await privateDeploymentOwner
                .acknowledgePersistence(
                    initialTransition,
                    exactReadback: exactReadback
                )
            guard case .awaitingInput(.discovery) = acknowledged else {
                throw Failure.invalidRecoveryState
            }
            return try await createFreshHost(
                account: account,
                binding: fusionBinding,
                privateDeploymentOwner: privateDeploymentOwner,
                walletReservationIdentifier: walletReservationIdentifier,
                walletGeneration: walletGeneration,
                profile: .opalMainnetAlpha,
                network: .mainnet,
                selectedInputs: selectedInputs,
                outputAmountsSatoshis: outputAmountsSatoshis,
                transactionReader: transactionReader,
                journalAttempt: journalAttempt
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.runtimeOperationFailed
        }
    }

    /// Creates and claims the sole application-facing session owner without returning
    /// a value whose hidden storage contains OpalFusion types to the app target.
    @_spi(MosaicPrivateAlpha)
    public static func createFreshApplicationSessionOwner(
        account: OpalBase.Account,
        binding: Binding,
        discoveryEpochStartUnixSeconds: UInt64,
        walletReservationIdentifier: UUID,
        walletGeneration: UInt64,
        selectedInputs: [OpalBase.Transaction.Output.Unspent],
        outputAmountsSatoshis: [UInt64],
        transactionReader: OpalBase.Network.TransactionReader,
        recoveryPersistence: FusionRecoveryPersistence,
        journalAttempt: consuming OpalBase.Account
            .MosaicPrivateAlphaJournal.FreshAttempt
    ) async throws -> SessionOwner {
        let host = try await createFreshApplicationHost(
            account: account,
            binding: binding,
            discoveryEpochStartUnixSeconds: discoveryEpochStartUnixSeconds,
            walletReservationIdentifier: walletReservationIdentifier,
            walletGeneration: walletGeneration,
            selectedInputs: selectedInputs,
            outputAmountsSatoshis: outputAmountsSatoshis,
            transactionReader: transactionReader,
            recoveryPersistence: recoveryPersistence,
            journalAttempt: journalAttempt
        )
        return try await host.makeSessionOwner()
    }

    /// Claims one authenticated recovery only when all protocol and wallet identities match exactly.
    static func loadRecoveryOwner(
        account: OpalBase.Account,
        expectedWalletReservationIdentifier: UUID,
        expectedWalletGeneration: UInt64,
        transactionReader: OpalBase.Network.TransactionReader,
        fusionRecovery: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .LoadedRecovery,
        journalRecovery: consuming OpalBase.Account
            .MosaicPrivateAlphaJournal.LoadedRecovery
    ) async throws -> RecoveryOwner {
        let binding = fusionRecovery.binding
        let state = journalRecovery.claimRecoveryState()
        guard let expected = OpalBase.Account.MosaicAttemptBinding(
            attemptIdentifier: binding.attemptIdentifier,
            generationIdentifier: binding.generationIdentifier,
            materialIdentifier: binding.materialIdentifier,
            walletReservationReference: .init(
                identifier: expectedWalletReservationIdentifier,
                generation: expectedWalletGeneration
            )
        ), state.binding == expected else {
            throw Failure.invalidBinding
        }
        do {
            let walletRecoveryOwner = try await account
                .makeMosaicPrivateAlphaRecoveryOwner(state: state)
            try await walletRecoveryOwner.prepareForDeterministicReplay()
            let privateDeploymentOwner = try OpalFusion
                .MosaicPrivateAlphaRuntime.Owner(
                    claiming: fusionRecovery
                )
            return .init(
                binding: binding,
                privateDeploymentOwner: privateDeploymentOwner,
                walletRecoveryOwner: walletRecoveryOwner,
                previousOutputSource: transactionReader
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let failure as OpalBase.Account
            .MosaicPrivateAlphaRecoveryOwner.Failure {
            throw Failure(failure)
        } catch {
            throw Failure.invalidRecoveryState
        }
    }

    /// Restores one exact private-alpha owner from opaque Fusion recovery bytes.
    @_spi(MosaicPrivateAlpha)
    public static func loadApplicationRecoveryOwner(
        account: OpalBase.Account,
        binding: Binding,
        expectedWalletReservationIdentifier: UUID,
        expectedWalletGeneration: UInt64,
        transactionReader: OpalBase.Network.TransactionReader,
        fusionRecoverySnapshot: Data,
        journalRecovery: consuming OpalBase.Account
            .MosaicPrivateAlphaJournal.LoadedRecovery
    ) async throws -> RecoveryOwner {
        do {
            let fusionRecovery = try OpalFusion.MosaicPrivateAlphaRuntime
                .loadRecovery(
                    from: fusionRecoverySnapshot,
                    expectedBinding: binding.fusionBinding
                )
            return try await loadRecoveryOwner(
                account: account,
                expectedWalletReservationIdentifier:
                    expectedWalletReservationIdentifier,
                expectedWalletGeneration: expectedWalletGeneration,
                transactionReader: transactionReader,
                fusionRecovery: fusionRecovery,
                journalRecovery: journalRecovery
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.invalidRecoveryState
        }
    }

    /// Restores and claims the sole application-facing session owner while keeping
    /// OpalFusion-backed recovery storage entirely inside OpalBase.
    @_spi(MosaicPrivateAlpha)
    public static func loadApplicationRecoverySessionOwner(
        account: OpalBase.Account,
        binding: Binding,
        expectedWalletReservationIdentifier: UUID,
        expectedWalletGeneration: UInt64,
        transactionReader: OpalBase.Network.TransactionReader,
        fusionRecoverySnapshot: Data,
        journalRecovery: consuming OpalBase.Account
            .MosaicPrivateAlphaJournal.LoadedRecovery
    ) async throws -> SessionOwner {
        let recoveryOwner = try await loadApplicationRecoveryOwner(
            account: account,
            binding: binding,
            expectedWalletReservationIdentifier:
                expectedWalletReservationIdentifier,
            expectedWalletGeneration: expectedWalletGeneration,
            transactionReader: transactionReader,
            fusionRecoverySnapshot: fusionRecoverySnapshot,
            journalRecovery: journalRecovery
        )
        return try await recoveryOwner.makeSessionOwner()
    }
}
#endif
