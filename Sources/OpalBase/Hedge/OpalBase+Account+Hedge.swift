// OpalBase+Account+Hedge.swift

import Foundation
import OpalDiagnostics
import OpalHedge

extension _OpalBase.Account {
    public func reserveHedgeParticipantMaterial(
        side: OpalBase.Hedge.Side = .hedge,
        network: OpalBase.Network.Environment = .mainnet
    ) async throws -> OpalBase.Hedge.ParticipantMaterial {
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("hedge_participant_material_reserve"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.network(network)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.hedgeParticipantMaterialReserveStarted,
                category: OpalDiagnostics.Category.hedge,
                fields: fields
            )
            do {
                try requirePrivateKeyMaterial()
                let entry = try await reserveNextReceivingEntry()
                do {
                    let signingKey = try await addressBook.generateSigningKey(
                        at: entry.derivationPath.index,
                        for: .receiving
                    )
                    let publicKey = signingKey.publicKey
                    let payoutAddress = try OpalBase.Address(
                        script: entry.address.lockingScript,
                        network: network
                    )

                    let material = OpalBase.Hedge.ParticipantMaterial(
                        side: side,
                        payoutAddress: payoutAddress,
                        lockingScriptHex: payoutAddress.lockingScript.data.hexadecimalString,
                        mutualRedeemPublicKeyHex: publicKey.compressedData.hexadecimalString,
                        derivedAddress: .init(
                            address: payoutAddress,
                            derivationPath: entry.derivationPath,
                            createdAt: entry.createdAt
                        )
                    )
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.hedgeParticipantMaterialReserved,
                        category: OpalDiagnostics.Category.hedge,
                        fields: fields
                    )
                    return material
                } catch {
                    _ = try? await addressBook.releaseReservation(
                        address: entry.address,
                        shouldKeepUsed: false
                    )
                    throw error
                }
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.hedgeParticipantMaterialReserveFailed,
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

    public func prepareHedgeFunding(
        _ request: OpalBase.Hedge.USDThirtyDaySimpleHedgeRequest,
        feePolicy: OpalBase.Wallet.FeePolicy = .init()
    ) async throws -> OpalBase.Hedge.FundingPlan {
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("hedge_funding_prepare"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.network(request.network)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.hedgeFundingPrepareStarted,
                category: OpalDiagnostics.Category.hedge,
                fields: fields
            )

            do {
                try requirePrivateKeyMaterial()
                let contractPlan = try OpalBase.Hedge.buildOpalHedgePlan(from: request)
                let fundingRequest = try OpalHedge.Client.Context()
                    .createAnyHedgeContractFundingRequest(
                        from: contractPlan,
                        network: OpalBase.Hedge.opalHedgeNetwork(for: request.network)
                    )
                let quote = try OpalBase.Hedge.makeFundingQuote(
                    from: fundingRequest,
                    network: request.network
                )
                let payment = OpalBase.Account.Payment(
                    recipients: [
                        .init(
                            address: quote.fundingAddress,
                            amount: quote.fundingAmount
                        )
                    ],
                    feeOverride: request.feeOverride,
                    feeContext: request.feeContext,
                    coinSelection: request.coinSelection,
                    tokenInputPolicy: .excludeTokenUTXOs,
                    shouldAllowDustDonation: false,
                    shouldAllowUnsafeTokenTransfers: false
                )
                let spendPlan = try await prepareSpend(payment, feePolicy: feePolicy)

                let plan = OpalBase.Hedge.FundingPlan(
                    quote: quote,
                    spendPlan: spendPlan,
                    contractPlan: contractPlan,
                    network: request.network
                )
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.hedgeFundingPrepareSucceeded,
                    category: OpalDiagnostics.Category.hedge,
                    fields: fields
                )
                return plan
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.hedgeFundingPrepareFailed,
                    category: OpalDiagnostics.Category.hedge,
                    fields: fields + OpalDiagnostics.Field.errorFields(
                        for: error,
                        errorCode: OpalDiagnostics.ErrorCode.hedgeFundingFailed
                    )
                )
                throw error
            }
        }
    }
}
