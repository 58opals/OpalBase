// OpalBase+WalletTransactionAuthoringInteractor.swift

public extension OpalBase {
    /// User-triggered money-movement lane for spend, token, claimable funding, hedge funding, and signing plans.
    struct WalletTransactionAuthoringInteractor: Sendable {
        let privateAccount: OpalBase.Account
        let feePolicy: OpalBase.Wallet.FeePolicy

        public init(
            privateAccount: OpalBase.Account,
            feePolicy: OpalBase.Wallet.FeePolicy = .init()
        ) {
            self.privateAccount = privateAccount
            self.feePolicy = feePolicy
        }

        public func prepareSpend(
            _ payment: OpalBase.Account.Payment
        ) async throws -> OpalBase.Account.SpendPlan {
            try await privateAccount.prepareSpend(payment, feePolicy: feePolicy)
        }

        public func prepareSpendForExternalReview(
            _ payment: OpalBase.Account.Payment,
            profile: OpalBase.WalletSecurityProfile = .offlineSavingsSigner,
            signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
            unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()
        ) async throws -> OpalBase.WalletUnsignedSpendPlan {
            try profile.requireSecureEnclaveSecretPersistence()
            try profile.requireExternalSigningReview()
            try profile.requireOfflineNetworkAccess()
            return try await privateAccount.prepareSpendForExternalReview(
                payment,
                feePolicy: feePolicy,
                signatureFormat: signatureFormat,
                unlockers: unlockers
            )
        }

        public func prepareTokenSpend(
            _ transfer: OpalBase.Account.TokenTransfer
        ) async throws -> OpalBase.Account.TokenSpendPlan {
            try await privateAccount.prepareTokenSpend(transfer, feePolicy: feePolicy)
        }

        public func prepareTokenGenesis(
            _ genesis: OpalBase.Account.TokenGenesis,
            preferredGenesisInput: OpalBase.Transaction.Output.Unspent? = nil
        ) async throws -> OpalBase.Account.TokenGenesisPlan {
            try await privateAccount.prepareTokenGenesis(
                genesis,
                preferredGenesisInput: preferredGenesisInput,
                feePolicy: feePolicy
            )
        }

        public func prepareTokenGenesisOutpoint(
            using entryUsage: OpalBase.Key.DerivationPath.Usage = .change
        ) async throws -> OpalBase.Account.SpendPlan {
            try await privateAccount.prepareTokenGenesisOutpoint(
                feePolicy: feePolicy,
                using: entryUsage
            )
        }

        public func prepareTokenMint(
            _ mint: OpalBase.Account.TokenMint,
            preferredMintingInput: OpalBase.Transaction.Output.Unspent? = nil
        ) async throws -> OpalBase.Account.TokenMintPlan {
            try await privateAccount.prepareTokenMint(
                mint,
                preferredMintingInput: preferredMintingInput,
                feePolicy: feePolicy
            )
        }

        public func prepareTokenCommitmentMutation(
            _ mutation: OpalBase.Account.TokenCommitmentMutation
        ) async throws -> OpalBase.Account.TokenCommitmentMutationPlan {
            try await privateAccount.prepareTokenCommitmentMutation(
                mutation,
                feePolicy: feePolicy
            )
        }

        public func reserveHedgeParticipantMaterial(
            side: OpalBase.Hedge.Side = .hedge,
            network: OpalBase.Network.Environment = .mainnet
        ) async throws -> OpalBase.Hedge.ParticipantMaterial {
            try await privateAccount.reserveHedgeParticipantMaterial(
                side: side,
                network: network
            )
        }

        public func prepareHedgeFunding(
            _ request: OpalBase.Hedge.USDThirtyDaySimpleHedgeRequest
        ) async throws -> OpalBase.Hedge.FundingPlan {
            try await privateAccount.prepareHedgeFunding(request, feePolicy: feePolicy)
        }
    }
}
