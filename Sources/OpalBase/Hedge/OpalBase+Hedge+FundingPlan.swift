// OpalBase+Hedge+FundingPlan.swift

import Foundation
import OpalDiagnostics
import OpalHedge

extension _OpalBase.Hedge {
    public struct FundingPlan: Sendable {
        public let quote: FundingQuote

        private let spendPlan: OpalBase.Account.SpendPlan
        private let contractPlan: OpalHedge.Core.ContractPlan
        private let network: OpalBase.Network.Environment

        init(
            quote: FundingQuote,
            spendPlan: OpalBase.Account.SpendPlan,
            contractPlan: OpalHedge.Core.ContractPlan,
            network: OpalBase.Network.Environment
        ) {
            self.quote = quote
            self.spendPlan = spendPlan
            self.contractPlan = contractPlan
            self.network = network
        }

        public var inputs: [OpalBase.Transaction.Output.Unspent] {
            spendPlan.inputs
        }

        public var targetAmount: OpalBase.Satoshi {
            spendPlan.targetAmount
        }

        public var totalSelectedAmount: OpalBase.Satoshi {
            spendPlan.totalSelectedAmount
        }

        public var feeRate: UInt64 {
            spendPlan.feeRate
        }

        public var reservationDate: Date {
            spendPlan.reservationDate
        }

        public func buildReview(
            signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
            unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()
        ) throws -> FundingReview {
            try OpalDiagnostics.withTraceID {
                let fields = [
                    OpalDiagnostics.Field.operation("hedge_funding_build"),
                    OpalDiagnostics.Field.module(),
                    OpalDiagnostics.Field.network(network)
                ]
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.hedgeFundingBuildStarted,
                    category: OpalDiagnostics.Category.hedge,
                    fields: fields
                )
                do {
                    let result = try spendPlan.buildTransaction(
                        signatureFormat: signatureFormat,
                        unlockers: unlockers
                    )
                    let review = try makeReview(from: result)
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.hedgeFundingBuildSucceeded,
                        category: OpalDiagnostics.Category.hedge,
                        fields: fields + [
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outputCount, review.transaction.outputs.count),
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.byteCount, review.rawTransactionByteCount)
                        ]
                    )
                    return review
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

        public func buildTransaction(
            signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
            unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()
        ) throws -> OpalBase.Transaction {
            try buildReview(
                signatureFormat: signatureFormat,
                unlockers: unlockers
            ).transaction
        }

        public func buildAndBroadcast(
            via handler: OpalBase.Network.TransactionClient,
            signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
            unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()
        ) async throws -> (
            hash: OpalBase.Transaction.Hash,
            review: FundingReview,
            fundingRecord: FundingRecord
        ) {
            try await OpalDiagnostics.withTraceID {
                let fields = [
                    OpalDiagnostics.Field.operation("hedge_funding_broadcast"),
                    OpalDiagnostics.Field.module(),
                    OpalDiagnostics.Field.network(network)
                ]
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.hedgeFundingBroadcastStarted,
                    category: OpalDiagnostics.Category.hedge,
                    fields: fields
                )
                do {
                    let broadcast = try await spendPlan.buildAndBroadcast(
                        via: handler,
                        signatureFormat: signatureFormat,
                        unlockers: unlockers
                    )
                    let review = try makeReview(from: broadcast.result)
                    let fundingRecord = try makeFundingRecord(
                        fundingTransactionHash: broadcast.hash,
                        fundingOutputIndex: review.fundingOutputIndex
                    )
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.hedgeFundingBroadcastSucceeded,
                        category: OpalDiagnostics.Category.hedge,
                        fields: fields + [
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outputCount, review.transaction.outputs.count),
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.byteCount, review.rawTransactionByteCount)
                        ]
                    )
                    return (broadcast.hash, review, fundingRecord)
                } catch {
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.hedgeFundingBroadcastFailed,
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

        func buildAndBroadcast(
            via handler: any OpalBase.Network.TransactionHandling,
            signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
            unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()
        ) async throws -> (
            hash: OpalBase.Transaction.Hash,
            review: FundingReview,
            fundingRecord: FundingRecord
        ) {
            try await buildAndBroadcast(
                via: .init(handler),
                signatureFormat: signatureFormat,
                unlockers: unlockers
            )
        }

        public func cancelReservation() async throws {
            try await spendPlan.cancelReservation()
        }

        public func completeReservation() async throws {
            try await spendPlan.completeReservation()
        }

        private func makeReview(
            from result: OpalBase.Account.SpendPlan.TransactionResult
        ) throws -> FundingReview {
            let outputIndex = try resolveFundingOutputIndex(
                in: result.transaction.outputs
            )
            let fundingOutput = result.transaction.outputs[Int(outputIndex)]
            return FundingReview(
                transaction: result.transaction,
                rawTransactionData: try result.transaction.encode(),
                fee: result.fee,
                change: result.change,
                fundingOutputIndex: outputIndex,
                fundingOutput: fundingOutput,
                quote: quote
            )
        }

        private func makeFundingRecord(
            fundingTransactionHash: OpalBase.Transaction.Hash,
            fundingOutputIndex: UInt32
        ) throws -> FundingRecord {
            let record = try OpalHedge.Client.Context()
                .createAnyHedgeContractFundingRecord(
                    from: contractPlan,
                    fundingTransactionHash: fundingTransactionHash.reverseOrder
                        .hexadecimalString,
                    fundingOutputIndex: Int64(fundingOutputIndex),
                    fundingSatoshis: Int64(quote.fundingAmount.uint64),
                    network: OpalBase.Hedge.opalHedgeNetwork(for: network)
                )
            return try OpalBase.Hedge.makeFundingRecord(
                from: record,
                network: network
            )
        }

        private func resolveFundingOutputIndex(
            in outputs: [OpalBase.Transaction.Output]
        ) throws -> UInt32 {
            let matches = outputs.enumerated().filter { _, output in
                output.value == quote.fundingAmount.uint64
                    && output.lockingScript == quote.fundingAddress.lockingScript.data
                    && output.tokenData == nil
            }
            guard matches.isEmpty == false else {
                throw Error.fundingOutputNotFound
            }
            guard matches.count == 1 else {
                throw Error.fundingOutputAmbiguous
            }
            guard let outputIndex = UInt32(exactly: matches[0].offset) else {
                throw Error.invalidFundingOutputIndex(Int64(matches[0].offset))
            }
            return outputIndex
        }
    }
}
