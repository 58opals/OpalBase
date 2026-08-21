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
            let privateDeploymentOwner = try OpalFusion
                .MosaicPrivateAlphaRuntime.Owner(
                    claiming: fusionAttempt
                )
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

    /// Creates the exact private-alpha protocol owner without exposing OpalFusion to the app target.
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
            return try await createFreshHost(
                account: account,
                fusionAttempt: fusionAttempt,
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
}
#endif
