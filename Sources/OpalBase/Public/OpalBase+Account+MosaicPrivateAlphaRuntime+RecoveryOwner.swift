// OpalBase+Account+MosaicPrivateAlphaRuntime+RecoveryOwner.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Exact Fusion and wallet-recovery capabilities claimed from one authenticated binding.
    ///
    /// Give ``transactionHost`` to Fusion deterministic replay before calling ``resume()``.
    /// The fallback resumes Base-only recovery and may terminalize a pre-sign wallet state.
    @_spi(MosaicPrivateAlpha)
    public struct RecoveryOwner: Sendable {
        /// Exact protocol identity used to correlate Fusion evidence with Base cleanup authority.
        @_spi(MosaicPrivateAlpha)
        public let binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding

        /// The sole Fusion transition owner restored from the matching snapshot.
        @_spi(MosaicPrivateAlpha)
        public let privateDeploymentOwner: OpalFusion
            .MosaicPrivateAlphaRuntime.Owner

        private let walletRecoveryOwner: OpalBase.Account
            .MosaicPrivateAlphaRecoveryOwner

        init(
            binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding,
            privateDeploymentOwner: OpalFusion.MosaicPrivateAlphaRuntime.Owner,
            walletRecoveryOwner: OpalBase.Account
                .MosaicPrivateAlphaRecoveryOwner
        ) {
            self.binding = binding
            self.privateDeploymentOwner = privateDeploymentOwner
            self.walletRecoveryOwner = walletRecoveryOwner
        }

        /// Recovery-only wallet callbacks for Fusion's deterministic admission replay.
        @_spi(MosaicPrivateAlpha)
        public var transactionHost:
            any OpalFusion.Host.MosaicCompleteTransactionHost {
            walletRecoveryOwner
        }

        @_spi(MosaicPrivateAlpha)
        public func resume() async throws -> Outcome {
            do {
                return .init(try await walletRecoveryOwner.resume())
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        /// Continues only a complete transaction that preserves every recovered local signature byte.
        @_spi(MosaicPrivateAlpha)
        public func commitRecoveredLocallySignedTransaction(
            transactionBytes: Data
        ) async throws -> Outcome {
            do {
                let transaction = try OpalFusion.Host
                    .MosaicCompleteTransaction(
                        transactionBytes: [UInt8](transactionBytes)
                    )
                return .init(
                    try await walletRecoveryOwner
                        .commitRecoveredLocallySignedTransaction(transaction)
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        /// Performs approval, write-ahead intent, exact-presence reconciliation, and at most one dispatch.
        @_spi(MosaicPrivateAlpha)
        public func broadcastRecoveredTransaction(
            securityProfile: OpalBase.WalletSecurityProfile,
            using transactionClient: OpalBase.Network.Fulcrum
                .TransactionClient,
            requestApproval: @escaping @Sendable (
                BroadcastApprovalRequest
            ) async throws -> Bool
        ) async throws -> ChainState {
            do {
                let state = try await walletRecoveryOwner
                    .broadcastRecoveredTransaction(
                    securityProfile: securityProfile,
                    using: .init(transactionClient),
                    requestApproval: { request in
                        guard let exactRequest = BroadcastApprovalRequest(
                            request
                        ) else {
                            return .rejected
                        }
                        return try await requestApproval(exactRequest)
                            ? .approved : .rejected
                    }
                )
                return .init(state)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        /// Records only exact present or authoritative-absence observations; unknown remains unjournaled.
        @_spi(MosaicPrivateAlpha)
        public func reconcileChain(
            using transactionClient: OpalBase.Network.Fulcrum
                .TransactionClient
        ) async throws -> ChainOutcome {
            do {
                return .init(
                    try await walletRecoveryOwner.reconcileChain(
                        using: .init(transactionClient)
                    )
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        /// Lets application finality policy approve only the latest exact confirmed observation.
        @_spi(MosaicPrivateAlpha)
        public func authorizeChainFinality(
            using authorize: @Sendable (ChainState) async throws -> Bool
        ) async throws -> TerminalDisposition {
            do {
                return .init(
                    try await walletRecoveryOwner
                        .authorizeChainFinality { state in
                        try await authorize(.init(state))
                    }
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }

        /// Durably authorizes exact-envelope erasure after a package-proven terminal disposition.
        @_spi(MosaicPrivateAlpha)
        public func authorizeJournalErasure() async throws
            -> OpalBase.Account.MosaicPrivateAlphaJournal.CleanupRequirement {
            do {
                return .init(
                    try await walletRecoveryOwner.authorizeJournalErasure()
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure(error)
            }
        }
    }
}
#endif
