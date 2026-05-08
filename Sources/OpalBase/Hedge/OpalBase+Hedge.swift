// OpalBase+Hedge.swift

import Foundation

extension OpalBase {
    /// Wallet-facing AnyHedge beta funding APIs exposed without requiring callers
    /// to import the lower-level hedge implementation package.
    public enum Hedge {}
}

extension _OpalBase.Hedge {
    public enum Side: Sendable, Equatable {
        case hedge
        case long
    }

    public struct OracleProofInput: Sendable, Equatable {
        public let messageHex: String
        public let signatureHex: String
        public let publicKeyHex: String

        public init(
            messageHex: String,
            signatureHex: String,
            publicKeyHex: String
        ) {
            self.messageHex = messageHex
            self.signatureHex = signatureHex
            self.publicKeyHex = publicKeyHex
        }
    }

    public struct ParticipantMaterial: Sendable, Equatable {
        public let side: Side
        public let payoutAddress: OpalBase.Address
        public let lockingScriptHex: String
        public let mutualRedeemPublicKeyHex: String
        public let derivedAddress: OpalBase.Account.DerivedAddress?

        public init(
            side: Side,
            payoutAddress: OpalBase.Address,
            lockingScriptHex: String,
            mutualRedeemPublicKeyHex: String,
            derivedAddress: OpalBase.Account.DerivedAddress? = nil
        ) {
            self.side = side
            self.payoutAddress = payoutAddress
            self.lockingScriptHex = lockingScriptHex.lowercased()
            self.mutualRedeemPublicKeyHex = mutualRedeemPublicKeyHex.lowercased()
            self.derivedAddress = derivedAddress
        }
    }

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

    public struct FundingQuote: Sendable, Equatable {
        public let fundingAddress: OpalBase.Address
        public let fundingAmount: OpalBase.Satoshi
        public let payoutAmount: OpalBase.Satoshi
        public let dustReserveAmount: OpalBase.Satoshi
        public let redeemScriptBytecode: Data
        public let contractDataDocumentJSON: String

        public init(
            fundingAddress: OpalBase.Address,
            fundingAmount: OpalBase.Satoshi,
            payoutAmount: OpalBase.Satoshi,
            dustReserveAmount: OpalBase.Satoshi,
            redeemScriptBytecode: Data,
            contractDataDocumentJSON: String
        ) {
            self.fundingAddress = fundingAddress
            self.fundingAmount = fundingAmount
            self.payoutAmount = payoutAmount
            self.dustReserveAmount = dustReserveAmount
            self.redeemScriptBytecode = redeemScriptBytecode
            self.contractDataDocumentJSON = contractDataDocumentJSON
        }
    }

    public struct FundingReview: Sendable {
        public let transaction: OpalBase.Transaction
        public let rawTransactionData: Data
        public let rawTransactionByteCount: Int
        public let fee: OpalBase.Satoshi
        public let change: OpalBase.Account.SpendPlan.TransactionResult.Change?
        public let fundingOutputIndex: UInt32
        public let fundingOutput: OpalBase.Transaction.Output
        public let quote: FundingQuote

        public init(
            transaction: OpalBase.Transaction,
            rawTransactionData: Data,
            fee: OpalBase.Satoshi,
            change: OpalBase.Account.SpendPlan.TransactionResult.Change?,
            fundingOutputIndex: UInt32,
            fundingOutput: OpalBase.Transaction.Output,
            quote: FundingQuote
        ) {
            self.transaction = transaction
            self.rawTransactionData = rawTransactionData
            self.rawTransactionByteCount = rawTransactionData.count
            self.fee = fee
            self.change = change
            self.fundingOutputIndex = fundingOutputIndex
            self.fundingOutput = fundingOutput
            self.quote = quote
        }
    }

    public struct FundingRecord: Sendable, Equatable {
        public let fundingAddress: OpalBase.Address
        public let fundingAmount: OpalBase.Satoshi
        public let fundingTransactionHash: OpalBase.Transaction.Hash
        public let fundingTransactionHashHex: String
        public let fundingOutputIndex: UInt32
        public let dataDocumentJSON: String

        public init(
            fundingAddress: OpalBase.Address,
            fundingAmount: OpalBase.Satoshi,
            fundingTransactionHash: OpalBase.Transaction.Hash,
            fundingOutputIndex: UInt32,
            dataDocumentJSON: String
        ) {
            self.fundingAddress = fundingAddress
            self.fundingAmount = fundingAmount
            self.fundingTransactionHash = fundingTransactionHash
            self.fundingTransactionHashHex = fundingTransactionHash.reverseOrder.hexadecimalString
            self.fundingOutputIndex = fundingOutputIndex
            self.dataDocumentJSON = dataDocumentJSON
        }
    }

    public struct SettlementSummary: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case maturation
            case liquidation
            case mutual
        }

        public let kind: Kind
        public let fundingTransactionHash: OpalBase.Transaction.Hash
        public let fundingTransactionHashHex: String
        public let fundingOutputIndex: UInt32
        public let fundingAmount: OpalBase.Satoshi
        public let settlementTransactionHash: OpalBase.Transaction.Hash
        public let settlementTransactionHashHex: String
        public let settlementPrice: Int64
        public let hedgePayoutAmount: OpalBase.Satoshi
        public let longPayoutAmount: OpalBase.Satoshi
        public let totalPayoutAmount: OpalBase.Satoshi
        public let minerFeeAmount: OpalBase.Satoshi
        public let previousOracleMessageHex: String
        public let previousOracleSignatureHex: String
        public let previousOracleTimestamp: Int64
        public let previousOracleSequence: Int64
        public let settlementOracleMessageHex: String
        public let settlementOracleSignatureHex: String
        public let settlementOracleTimestamp: Int64
        public let settlementOracleSequence: Int64
        public let dataDocumentJSON: String

        public init(
            kind: Kind,
            fundingTransactionHash: OpalBase.Transaction.Hash,
            fundingOutputIndex: UInt32,
            fundingAmount: OpalBase.Satoshi,
            settlementTransactionHash: OpalBase.Transaction.Hash,
            settlementPrice: Int64,
            hedgePayoutAmount: OpalBase.Satoshi,
            longPayoutAmount: OpalBase.Satoshi,
            totalPayoutAmount: OpalBase.Satoshi,
            minerFeeAmount: OpalBase.Satoshi,
            previousOracleMessageHex: String,
            previousOracleSignatureHex: String,
            previousOracleTimestamp: Int64,
            previousOracleSequence: Int64,
            settlementOracleMessageHex: String,
            settlementOracleSignatureHex: String,
            settlementOracleTimestamp: Int64,
            settlementOracleSequence: Int64,
            dataDocumentJSON: String
        ) {
            self.kind = kind
            self.fundingTransactionHash = fundingTransactionHash
            self.fundingTransactionHashHex = fundingTransactionHash.reverseOrder.hexadecimalString
            self.fundingOutputIndex = fundingOutputIndex
            self.fundingAmount = fundingAmount
            self.settlementTransactionHash = settlementTransactionHash
            self.settlementTransactionHashHex = settlementTransactionHash.reverseOrder.hexadecimalString
            self.settlementPrice = settlementPrice
            self.hedgePayoutAmount = hedgePayoutAmount
            self.longPayoutAmount = longPayoutAmount
            self.totalPayoutAmount = totalPayoutAmount
            self.minerFeeAmount = minerFeeAmount
            self.previousOracleMessageHex = previousOracleMessageHex
            self.previousOracleSignatureHex = previousOracleSignatureHex
            self.previousOracleTimestamp = previousOracleTimestamp
            self.previousOracleSequence = previousOracleSequence
            self.settlementOracleMessageHex = settlementOracleMessageHex
            self.settlementOracleSignatureHex = settlementOracleSignatureHex
            self.settlementOracleTimestamp = settlementOracleTimestamp
            self.settlementOracleSequence = settlementOracleSequence
            self.dataDocumentJSON = dataDocumentJSON
        }
    }

    public enum Error: Swift.Error, Sendable, Equatable {
        case unsupportedWalletSide(Side)
        case unsupportedCounterpartySide(Side)
        case networkMismatch(expected: OpalBase.Network.Environment, actual: OpalBase.Network.Environment)
        case invalidFundingAmount(Int64)
        case invalidFundingOutputIndex(Int64)
        case invalidTransactionHash(String)
        case oraclePublicKeyMismatch(expected: String, actual: String)
        case fundingOutputNotFound
        case fundingOutputAmbiguous
    }
}
