// OpalBase+Hedge~OpalHedge.swift

import Foundation
import OpalDiagnostics
import OpalHedge

extension _OpalBase.Hedge.Side {
    var opalHedgeContractSide: OpalHedge.Core.ContractSide {
        switch self {
        case .hedge:
            return .short
        case .long:
            return .long
        }
    }
}

extension _OpalBase.Hedge {
    static func opalHedgeNetwork(
        for network: OpalBase.Network.Environment
    ) -> OpalHedge.BitcoinCash.Network {
        switch network {
        case .mainnet:
            return .mainnet
        case .chipnet, .testnet:
            return .testnet
        }
    }

    static func buildOpalHedgePlan(
        from request: USDThirtyDaySimpleHedgeRequest
    ) throws -> OpalHedge.Core.ContractPlan {
        try validateRequest(request)

        let startingProof = try OpalHedge.Oracle.verifyStartingPriceProof(
            messageHex: request.startingOracleProof.messageHex,
            signatureHex: request.startingOracleProof.signatureHex,
            publicKeyHex: request.startingOracleProof.publicKeyHex
        )
        let preset = OpalHedge.Core.ContractPreset.usdSimpleHedgeThirtyDay
        let maturityTimestamp = try request.maturityTimestamp
            ?? (OpalHedge.Oracle.PriceMessage.parse(
                hex: request.startingOracleProof.messageHex
            ).messageTimestamp + preset.durationInSeconds)
        let context = try OpalHedge.Core.ContractCreationContext(
            takerSide: request.walletParticipant.side.opalHedgeContractSide,
            makerSide: request.counterpartyParticipant.side.opalHedgeContractSide,
            startingOracleProof: startingProof,
            shortPayoutAddress: request.walletParticipant.payoutAddress.generateString(
                withPrefix: true
            ),
            longPayoutAddress: request.counterpartyParticipant.payoutAddress.generateString(
                withPrefix: true
            ),
            shortLockScriptHex: request.walletParticipant.lockingScriptHex,
            longLockScriptHex: request.counterpartyParticipant.lockingScriptHex,
            nominalUnits: request.nominalUnits,
            maturityTimestamp: maturityTimestamp,
            isSimpleHedge: preset.isSimpleHedge,
            highLiquidationPriceMultiplier: preset.highLiquidationPriceMultiplier,
            lowLiquidationPriceMultiplier: preset.lowLiquidationPriceMultiplier,
            enableMutualRedemption: 1,
            shortMutualRedeemPublicKeyHex: request.walletParticipant
                .mutualRedeemPublicKeyHex,
            longMutualRedeemPublicKeyHex: request.counterpartyParticipant
                .mutualRedeemPublicKeyHex,
            minerCostInSatoshis: request.minerCostInSatoshis
        )

        return try OpalHedge.Core.ContractPlan(from: context)
    }

    static func validateRequest(_ request: USDThirtyDaySimpleHedgeRequest) throws {
        guard request.walletParticipant.side == .hedge else {
            throw Error.unsupportedWalletSide(request.walletParticipant.side)
        }
        guard request.counterpartyParticipant.side == .long else {
            throw Error.unsupportedCounterpartySide(request.counterpartyParticipant.side)
        }
        try validateNetwork(request.network, matches: request.walletParticipant)
        try validateNetwork(request.network, matches: request.counterpartyParticipant)
    }

    static func validateNetwork(
        _ expected: OpalBase.Network.Environment,
        matches participant: ParticipantMaterial
    ) throws {
        guard participant.payoutAddress.network == expected else {
            throw Error.networkMismatch(
                expected: expected,
                actual: participant.payoutAddress.network
            )
        }
    }

    static func makeFundingQuote(
        from request: OpalHedge.BitcoinCash.AnyHedgeContractFundingRequest,
        network: OpalBase.Network.Environment
    ) throws -> FundingQuote {
        let output = request.fundingOutput
        return FundingQuote(
            fundingAddress: try OpalBase.Address(
                string: output.contractAddress.rawValue,
                network: network
            ),
            fundingAmount: try satoshi(from: output.satoshis),
            payoutAmount: try satoshi(from: output.payoutSatoshis),
            dustReserveAmount: try satoshi(from: output.dustReserveSatoshis),
            redeemScriptBytecode: request.redeemScriptBytecode,
            contractDataDocumentJSON: request.contractDataDocument.jsonText
        )
    }

    static func makeFundingRecord(
        from record: OpalHedge.BitcoinCash.AnyHedgeContractFundingRecord,
        network: OpalBase.Network.Environment
    ) throws -> FundingRecord {
        let fundingOutputIndex = try uint32(fromFundingOutputIndex: record.funding.fundingOutputIndex)
        let fundingTransactionHash = try transactionHash(fromExternalHex: record.funding.fundingTransactionHash)
        return FundingRecord(
            fundingAddress: try OpalBase.Address(
                string: record.fundingOutput.contractAddress.rawValue,
                network: network
            ),
            fundingAmount: try satoshi(from: record.funding.fundingSatoshis),
            fundingTransactionHash: fundingTransactionHash,
            fundingOutputIndex: fundingOutputIndex,
            dataDocumentJSON: record.dataDocument.jsonText
        )
    }

    static func makeSettlementSummary(
        from summary: OpalHedge.BitcoinCash.AnyHedgeContractSettlementSummary,
        network _: OpalBase.Network.Environment
    ) throws -> SettlementSummary {
        let fundingHash = try transactionHash(fromExternalHex: summary.fundingTransactionHash)
        let settlementHash = try transactionHash(fromExternalHex: summary.settlementTransactionHash)
        return SettlementSummary(
            kind: settlementKind(from: summary.settlementKind),
            fundingTransactionHash: fundingHash,
            fundingOutputIndex: try uint32(fromFundingOutputIndex: summary.fundingOutputIndex),
            fundingAmount: try satoshi(from: summary.fundingSatoshis),
            settlementTransactionHash: settlementHash,
            settlementPrice: summary.settlementPrice,
            hedgePayoutAmount: try satoshi(from: summary.hedgePayoutInSatoshis),
            longPayoutAmount: try satoshi(from: summary.longPayoutInSatoshis),
            totalPayoutAmount: try satoshi(from: summary.totalPayoutInSatoshis),
            minerFeeAmount: try satoshi(from: summary.minerFeeInSatoshis),
            previousOracleMessageHex: summary.previousOracleMessageHex,
            previousOracleSignatureHex: summary.previousOracleSignatureHex,
            previousOracleTimestamp: summary.previousOracleMessageTimestamp,
            previousOracleSequence: summary.previousOracleMessageSequence,
            settlementOracleMessageHex: summary.settlementOracleMessageHex,
            settlementOracleSignatureHex: summary.settlementOracleSignatureHex,
            settlementOracleTimestamp: summary.settlementOracleMessageTimestamp,
            settlementOracleSequence: summary.settlementOracleMessageSequence,
            dataDocumentJSON: summary.dataDocument.jsonText
        )
    }

    static func satoshi(from value: Int64) throws -> OpalBase.Satoshi {
        guard value >= 0 else { throw Error.invalidFundingAmount(value) }
        return try OpalBase.Satoshi(UInt64(value))
    }

    static func uint32(fromFundingOutputIndex value: Int64) throws -> UInt32 {
        guard let outputIndex = UInt32(exactly: value) else {
            throw Error.invalidFundingOutputIndex(value)
        }
        return outputIndex
    }

    static func transactionHash(fromExternalHex hex: String) throws -> OpalBase.Transaction.Hash {
        guard !hex.hasPrefix("0x"), !hex.hasPrefix("0X") else {
            throw Error.invalidTransactionHash(hex)
        }
        let data: Data
        do {
            data = try Data(hexadecimalString: hex)
        } catch {
            throw Error.invalidTransactionHash(hex)
        }
        guard data.count == OpalBase.Transaction.Hash.expectedByteCount else {
            throw Error.invalidTransactionHash(hex)
        }
        return OpalBase.Transaction.Hash(reverseOrder: data)
    }

    static func settlementKind(
        from kind: OpalHedge.Core.SettlementKind
    ) -> SettlementSummary.Kind {
        switch kind {
        case .maturation:
            return .maturation
        case .liquidation:
            return .liquidation
        case .mutual:
            return .mutual
        }
    }
}

extension _OpalBase.Hedge {
    public static func makeFundingRecord(
        dataDocumentJSON: String,
        fundingIndex: Int = 0,
        network: OpalBase.Network.Environment = .mainnet
    ) throws -> FundingRecord {
        try OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("hedge_funding_record_make"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.network(network)
            ]
            do {
                let dataDocument = try OpalHedge.Core.ContractDataDocument(
                    jsonText: dataDocumentJSON
                )
                let record = try OpalHedge.Client.Context()
                    .createAnyHedgeContractFundingRecord(
                        from: dataDocument,
                        fundingIndex: fundingIndex,
                        network: opalHedgeNetwork(for: network)
                    )
                let fundingRecord = try makeFundingRecord(from: record, network: network)
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.hedgeFundingBuildSucceeded,
                    category: OpalDiagnostics.Category.hedge,
                    fields: fields
                )
                return fundingRecord
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.hedgeFundingBuildFailed,
                    category: OpalDiagnostics.Category.hedge,
                    fields: fields + OpalDiagnostics.Field.errorFields(
                        for: error,
                        fallback: OpalDiagnostics.ErrorCode.hedgeFundingFailed
                    )
                )
                throw error
            }
        }
    }

    public static func makeSettlementSummary(
        fundingDataDocumentJSON: String,
        fundingIndex: Int = 0,
        previousOracleProof: OracleProofInput,
        settlementOracleProof: OracleProofInput,
        settlementTransactionHash: OpalBase.Transaction.Hash,
        network: OpalBase.Network.Environment = .mainnet
    ) throws -> SettlementSummary {
        try OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("hedge_settlement_summary_make"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.network(network)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.hedgeSettlementResolveStarted,
                category: OpalDiagnostics.Category.hedge,
                fields: fields
            )
            do {
                let dataDocument = try OpalHedge.Core.ContractDataDocument(
                    jsonText: fundingDataDocumentJSON
                )
                let fundingRecord = try OpalHedge.Client.Context()
                    .createAnyHedgeContractFundingRecord(
                        from: dataDocument,
                        fundingIndex: fundingIndex,
                        network: opalHedgeNetwork(for: network)
                    )
                try validateSettlementOraclePublicKey(
                    fundingRecord.draftData.parameters.oraclePublicKeyHex,
                    matches: previousOracleProof
                )
                try validateSettlementOraclePublicKey(
                    fundingRecord.draftData.parameters.oraclePublicKeyHex,
                    matches: settlementOracleProof
                )
                let previousProof = try OpalHedge.Oracle.verifySettlementOracleProof(
                    messageHex: previousOracleProof.messageHex,
                    signatureHex: previousOracleProof.signatureHex,
                    publicKeyHex: previousOracleProof.publicKeyHex
                )
                let settlementProof = try OpalHedge.Oracle.verifySettlementOracleProof(
                    messageHex: settlementOracleProof.messageHex,
                    signatureHex: settlementOracleProof.signatureHex,
                    publicKeyHex: settlementOracleProof.publicKeyHex
                )
                let settlementRecord = try fundingRecord
                    .createSettlementRequest(
                        previousOracleProof: previousProof,
                        settlementOracleProof: settlementProof
                    )
                    .createSettlementRecord(
                        settlementTransactionHash: settlementTransactionHash.reverseOrder
                            .hexadecimalString
                    )

                let summary = try makeSettlementSummary(
                    from: settlementRecord.settlementSummary,
                    network: network
                )
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.hedgeSettlementResolveSucceeded,
                    category: OpalDiagnostics.Category.hedge,
                    fields: fields
                )
                return summary
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.hedgeSettlementResolveFailed,
                    category: OpalDiagnostics.Category.hedge,
                    fields: fields + OpalDiagnostics.Field.errorFields(
                        for: error,
                        fallback: OpalDiagnostics.ErrorCode.hedgeSettlementFailed
                    )
                )
                throw error
            }
        }
    }

    static func validateSettlementOraclePublicKey(
        _ expected: String,
        matches proof: OracleProofInput
    ) throws {
        let expectedLowercase = expected.lowercased()
        let actualLowercase = proof.publicKeyHex.lowercased()
        guard expectedLowercase == actualLowercase else {
            throw Error.oraclePublicKeyMismatch(
                expected: expectedLowercase,
                actual: actualLowercase
            )
        }
    }
}
