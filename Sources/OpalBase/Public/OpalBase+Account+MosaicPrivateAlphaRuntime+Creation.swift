// OpalBase+Account+MosaicPrivateAlphaRuntime+Creation.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Persists the exact cross-package binding before returning a live wallet host.
    @_spi(MosaicPrivateAlpha)
    public static func createFreshHost(
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
                privateDeploymentOwner: privateDeploymentOwner,
                transactionHost: try await account.makeMosaicTransactionHost(
                    profile: profile,
                    network: network,
                    attemptBinding: attemptBinding,
                    selectedInputs: selectedInputs,
                    outputAmountsSatoshis: outputAmountsSatoshis,
                    transactionReader: transactionReader,
                    freshAttempt: freshAttempt
                )
            )
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw Failure(error)
        }
    }

    /// Claims one authenticated recovery only when all protocol and wallet identities match exactly.
    @_spi(MosaicPrivateAlpha)
    public static func loadRecoveryOwner(
        account: OpalBase.Account,
        expectedWalletReservationIdentifier: UUID,
        expectedWalletGeneration: UInt64,
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
                walletRecoveryOwner: walletRecoveryOwner
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
}
#endif
