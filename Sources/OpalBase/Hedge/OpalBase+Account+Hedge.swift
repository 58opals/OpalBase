// OpalBase+Account+Hedge.swift

import Foundation
import OpalHedge

extension _OpalBase.Account {
    public func reserveHedgeParticipantMaterial(
        side: OpalBase.Hedge.Side = .hedge,
        network: OpalBase.Network.Environment = .mainnet
    ) async throws -> OpalBase.Hedge.ParticipantMaterial {
        try await OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("hedge_participant_material_reserve"),
                OpalBaseDiagnostics.moduleField(),
                OpalBaseDiagnostics.networkField(network)
            ]
            do {
                let entry = try await reserveNextReceivingEntry()
                let privateKeyData = try await addressBook.generatePrivateKey(
                    at: entry.derivationPath.index,
                    for: .receiving
                )
                let publicKey = try OpalBase.Key.PublicKey(privateKeyData: privateKeyData)
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
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.hedgeParticipantMaterialReserved,
                    category: OpalBase.Diagnostics.Categories.hedge,
                    fields: fields
                )
                return material
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.addressReserveFailed,
                    category: OpalBase.Diagnostics.Categories.hedge,
                    fields: fields + OpalBaseDiagnostics.errorFields(
                        for: error,
                        fallback: OpalBase.Diagnostics.ErrorCodes.hedgeFundingFailed
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
        try await OpalBase.Diagnostics.withTraceID {
            let traceID = OpalBase.Diagnostics.currentTraceID ?? OpalBase.Diagnostics.TraceID()
            return try await OpalBaseHedgeDiagnostics.withTraceID(traceID) {
                let fields = [
                    OpalBaseDiagnostics.operationField("hedge_funding_prepare"),
                    OpalBaseDiagnostics.moduleField(),
                    OpalBaseDiagnostics.networkField(request.network)
                ]
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.hedgeFundingPrepareStarted,
                    category: OpalBase.Diagnostics.Categories.hedge,
                    fields: fields
                )

                do {
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
                    OpalBaseDiagnostics.record(
                        OpalBase.Diagnostics.Events.hedgeFundingPrepareSucceeded,
                        category: OpalBase.Diagnostics.Categories.hedge,
                        fields: fields
                    )
                    return plan
                } catch {
                    OpalBaseDiagnostics.record(
                        OpalBase.Diagnostics.Events.hedgeFundingPrepareFailed,
                        category: OpalBase.Diagnostics.Categories.hedge,
                        fields: fields + OpalBaseDiagnostics.errorFields(
                            for: error,
                            fallback: OpalBase.Diagnostics.ErrorCodes.hedgeFundingFailed
                        )
                    )
                    throw error
                }
            }
        }
    }
}
