// HedgeFundingFacadeValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Hedge funding facade", .tags(.unit, .wallet, .transaction))
struct HedgeFundingFacadeValidator {
    @Test("reserves participant material from receiving address")
    func reservesParticipantMaterialFromReceivingAddress() async throws {
        let account = try await AccountTestFixtures.makeAccount()

        let material = try await account.reserveHedgeParticipantMaterial(
            network: .chipnet
        )

        let receivingEntries = await account.addressBook.listEntries(for: .receiving)
        let reservedEntry = try #require(receivingEntries.first)
        #expect(material.side == .hedge)
        #expect(material.payoutAddress.network == .chipnet)
        #expect(material.payoutAddress.generateString(withPrefix: true).hasPrefix("bchtest:"))
        #expect(material.payoutAddress.lockingScript == reservedEntry.address.lockingScript)
        #expect(material.derivedAddress?.derivationPath == reservedEntry.derivationPath)
        #expect(material.lockingScriptHex == material.payoutAddress.lockingScript.data.hexadecimalString)
        #expect(material.mutualRedeemPublicKeyHex.count == 66)
        #expect(reservedEntry.isReserved)
    }

    @Test("builds stable beta funding quote")
    func buildsStableBetaFundingQuote() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 6_000_000,
            hashByte: 0x90
        )

        let plan = try await account.prepareHedgeFunding(
            HedgeFixtureData.betaRequest()
        )

        #expect(plan.quote.fundingAddress.generateString(withPrefix: true) ==
            HedgeFixtureData.expectedFundingAddress)
        #expect(plan.quote.fundingAmount.uint64 ==
            HedgeFixtureData.expectedFundingSatoshis)
        #expect(plan.quote.payoutAmount.uint64 ==
            HedgeFixtureData.expectedPayoutSatoshis)
        #expect(plan.quote.dustReserveAmount.uint64 == 1_332)
        #expect(plan.quote.redeemScriptBytecode.isEmpty == false)
        #expect(plan.quote.contractDataDocumentJSON.contains(#""fundings":[]"#))
        try await plan.cancelReservation()
    }

    @Test("excludes token UTXOs and reports funding output index")
    func excludesTokenUTXOsAndReportsFundingOutputIndex() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x91, count: 32)
        )
        let tokenInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 10_000_000,
            tokenData: .init(category: category, amount: 1, nft: nil),
            hashByte: 0x92
        )
        let bchInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 6_000_000,
            hashByte: 0x93
        )

        let plan = try await account.prepareHedgeFunding(
            HedgeFixtureData.betaRequest()
        )
        let review = try plan.buildReview()

        #expect(plan.inputs.contains(tokenInput) == false)
        #expect(plan.inputs.contains(bchInput))
        #expect(review.fundingOutput.value == plan.quote.fundingAmount.uint64)
        #expect(review.fundingOutput.lockingScript ==
            plan.quote.fundingAddress.lockingScript.data)
        #expect(review.transaction.outputs[Int(review.fundingOutputIndex)] ==
            review.fundingOutput)
        #expect(review.rawTransactionByteCount == review.rawTransactionData.count)
        try await plan.cancelReservation()
    }

    @Test("chipnet funding maps to bchtest contract address")
    func chipnetFundingMapsToBCHTestContractAddress() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 6_000_000,
            hashByte: 0x97
        )

        let plan = try await account.prepareHedgeFunding(
            HedgeFixtureData.betaRequest(network: .chipnet)
        )

        #expect(plan.quote.fundingAddress.network == .chipnet)
        #expect(plan.quote.fundingAddress.generateString(withPrefix: true)
            .hasPrefix("bchtest:"))
        try await plan.cancelReservation()
    }

    @Test("broadcast success creates funding record")
    func broadcastSuccessCreatesFundingRecord() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 6_000_000,
            hashByte: 0x94
        )
        let plan = try await account.prepareHedgeFunding(
            HedgeFixtureData.betaRequest()
        )
        let handler = TransactionHandlingTestActor(
            deriveBroadcastTransactionHash: true
        )

        let result = try await plan.buildAndBroadcast(via: handler)

        let broadcasts = await handler.readBroadcastedTransactions()
        let expectedHash = try expectedBroadcastHash(from: broadcasts)
        let reconstructedRecord = try OpalBase.Hedge.makeFundingRecord(
            dataDocumentJSON: result.fundingRecord.dataDocumentJSON
        )
        #expect(result.hash == expectedHash)
        #expect(result.fundingRecord.fundingTransactionHash == expectedHash)
        #expect(reconstructedRecord == result.fundingRecord)
        #expect(result.fundingRecord.fundingAmount.uint64 ==
            HedgeFixtureData.expectedFundingSatoshis)
        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("broadcast failure leaves funding reservation cancellable")
    func broadcastFailureLeavesFundingReservationCancellable() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 6_000_000,
            hashByte: 0x95
        )
        let plan = try await account.prepareHedgeFunding(
            HedgeFixtureData.betaRequest()
        )
        let handler = TransactionHandlingTestActor(
            broadcastResult: .failure(NetworkStubError.forced("hedge-failure"))
        )

        do {
            _ = try await plan.buildAndBroadcast(via: handler)
            Issue.record("Expected hedge funding broadcast to throw")
        } catch let error as OpalBase.Account.Error {
            guard case .broadcastFailed = error else {
                Issue.record("Expected broadcastFailed but got \(error)")
                return
            }
        }

        #expect(await account.addressBook.readActiveSpendReservations().isEmpty == false)
        try await plan.cancelReservation()
        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("settlement summary matures and reconstructs from persisted funding document")
    func settlementSummaryMaturesAndReconstructsFromPersistedFundingDocument() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 6_000_000,
            hashByte: 0x96
        )
        let startingProof = try HedgeFixtureData.signedBetaRequest().startingOracleProof
        let plan = try await account.prepareHedgeFunding(
            HedgeFixtureData.signedBetaRequest()
        )
        let result = try await plan.buildAndBroadcast(
            via: TransactionHandlingTestActor(deriveBroadcastTransactionHash: true)
        )
        let settlementProof = try HedgeFixtureData.signedSettlementOracleProof()

        let summary = try OpalBase.Hedge.makeSettlementSummary(
            fundingDataDocumentJSON: result.fundingRecord.dataDocumentJSON,
            previousOracleProof: startingProof,
            settlementOracleProof: settlementProof,
            settlementTransactionHash: HedgeFixtureData.settlementTransactionHash
        )
        let reconstructedSummary = try OpalBase.Hedge.makeSettlementSummary(
            fundingDataDocumentJSON: result.fundingRecord.dataDocumentJSON,
            previousOracleProof: startingProof,
            settlementOracleProof: settlementProof,
            settlementTransactionHash: HedgeFixtureData.settlementTransactionHash
        )

        #expect(reconstructedSummary == summary)
        #expect(summary.kind == .maturation)
        #expect(summary.settlementPrice == HedgeFixtureData.expectedSettlementPrice)
        #expect(summary.hedgePayoutAmount.uint64 ==
            HedgeFixtureData.expectedHedgePayoutSatoshis)
        #expect(summary.longPayoutAmount.uint64 ==
            HedgeFixtureData.expectedLongPayoutSatoshis)
        #expect(summary.totalPayoutAmount.uint64 ==
            HedgeFixtureData.expectedPayoutSatoshis)
        #expect(summary.dataDocumentJSON.contains(#""settlementType":"maturation""#))
    }

    @Test("transaction hash parser rejects RPC-prefixed hex")
    func transactionHashParserRejectsRPCPrefixedHex() {
        let prefixedHash = "0x\(HedgeFixtureData.settlementTransactionHashHex)"

        #expect(throws: OpalBase.Hedge.Error.invalidTransactionHash(prefixedHash)) {
            _ = try OpalBase.Hedge.transactionHash(fromExternalHex: prefixedHash)
        }
    }
}
