// OpalBase+Hedge+USDThirtyDaySimpleHedgeRequest.swift

extension _OpalBase.Hedge {
    public struct USDThirtyDaySimpleHedgeRequest: Sendable {
        public let walletParticipant: ParticipantMaterial
        public let counterpartyParticipant: ParticipantMaterial
        public let startingOracleProof: OracleProofInput
        public let nominalUnits: Double
        public let maturityTimestamp: Int64?
        public let minerCostInSatoshis: Int64
        public let network: OpalBase.Network.Environment
        public let feeOverride: OpalBase.Wallet.FeePolicy.Override?
        public let feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext
        public let coinSelection: OpalBase.Account.CoinSelectionStrategy

        public init(
            walletParticipant: ParticipantMaterial,
            counterpartyParticipant: ParticipantMaterial,
            startingOracleProof: OracleProofInput,
            nominalUnits: Double,
            maturityTimestamp: Int64? = nil,
            minerCostInSatoshis: Int64 = 632,
            network: OpalBase.Network.Environment = .mainnet,
            feeOverride: OpalBase.Wallet.FeePolicy.Override? = nil,
            feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
            coinSelection: OpalBase.Account.CoinSelectionStrategy = .branchAndBound
        ) {
            self.walletParticipant = walletParticipant
            self.counterpartyParticipant = counterpartyParticipant
            self.startingOracleProof = startingOracleProof
            self.nominalUnits = nominalUnits
            self.maturityTimestamp = maturityTimestamp
            self.minerCostInSatoshis = minerCostInSatoshis
            self.network = network
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.coinSelection = coinSelection
        }
    }
}
