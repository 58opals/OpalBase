// HedgeFundingFacadeValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Hedge funding facade", .tags(.unit, .wallet, .transaction))
struct HedgeFundingFacadeValidator {
    @Test("funding models normalize sliced byte buffers")
    func fundingModelsNormalizeSlicedByteBuffers() throws {
        let redeemScriptBytecode = Data([0x51, 0x52])
        let paddedRedeemScriptBytecode = Data([0x00]) + redeemScriptBytecode
        let slicedRedeemScriptBytecode = paddedRedeemScriptBytecode[
            paddedRedeemScriptBytecode.index(after: paddedRedeemScriptBytecode.startIndex)...
        ]
        let fundingOutput = OpalBase.Transaction.Output(
            value: 10_000,
            lockingScript: Data([0x51])
        )
        let transaction = OpalBase.Transaction(
            version: 1,
            inputs: [],
            outputs: [fundingOutput],
            lockTime: 0
        )
        let quote = OpalBase.Hedge.FundingQuote(
            fundingAddress: try HedgeFixtureData.shortParticipant().payoutAddress,
            fundingAmount: try OpalBase.Satoshi(10_000),
            payoutAmount: try OpalBase.Satoshi(9_000),
            dustReserveAmount: try OpalBase.Satoshi(1_000),
            redeemScriptBytecode: slicedRedeemScriptBytecode,
            contractDataDocumentJSON: "{}"
        )
        let rawTransactionData = Data([0x01, 0x02, 0x03])
        let paddedRawTransactionData = Data([0x00]) + rawTransactionData
        let slicedRawTransactionData = paddedRawTransactionData[
            paddedRawTransactionData.index(after: paddedRawTransactionData.startIndex)...
        ]

        let review = OpalBase.Hedge.FundingReview(
            transaction: transaction,
            rawTransactionData: slicedRawTransactionData,
            fee: try OpalBase.Satoshi(500),
            change: nil,
            fundingOutputIndex: 0,
            fundingOutput: fundingOutput,
            quote: quote
        )

        #expect(slicedRedeemScriptBytecode.startIndex != 0)
        #expect(slicedRawTransactionData.startIndex != 0)
        #expect(quote.redeemScriptBytecode == redeemScriptBytecode)
        #expect(quote.redeemScriptBytecode.startIndex == 0)
        #expect(review.rawTransactionData == rawTransactionData)
        #expect(review.rawTransactionData.startIndex == 0)
        #expect(review.rawTransactionByteCount == rawTransactionData.count)
    }

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

    @Test("participant material reservation releases receiving entry when signing key derivation fails")
    func participantMaterialReservationReleasesReceivingEntryWhenSigningKeyDerivationFails() async throws {
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        let accountPath = try OpalBase.Key.DerivationPath.Account(rawIndexInteger: 0)
        let accountExtendedPublicKey = try OpalCryptoAdapter.makeAccountExtendedPublicKey(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: accountPath
        )
        let publicOnlyAddressBook = try await OpalBase.Address.Book(
            accountExtendedPublicKey: accountExtendedPublicKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: accountPath
        )
        let account = try OpalBase.Account(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: accountPath,
            addressBook: publicOnlyAddressBook
        )

        await #expect(throws: OpalBase.Address.Book.Error.privateKeyNotFound) {
            _ = try await account.reserveHedgeParticipantMaterial(network: .chipnet)
        }

        let receivingEntry = try #require(await publicOnlyAddressBook.listEntries(for: .receiving).first)
        #expect(receivingEntry.isUsed == false)
        #expect(receivingEntry.isReserved == false)
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

    @Test(
        "funding request rejects participant locking script mismatches",
        arguments: participantLockingScriptMismatchCases
    )
    func fundingRequestRejectsParticipantLockingScriptMismatches(
        _ mismatchCase: (side: OpalBase.Hedge.Side, mismatchedLockingScriptHex: String)
    ) throws {
        let validWalletParticipant = try HedgeFixtureData.shortParticipant()
        let validCounterpartyParticipant = try HedgeFixtureData.longParticipant()
        let walletParticipant = mismatchCase.side == .hedge
            ? Self.makeParticipantMaterial(
                from: validWalletParticipant,
                lockingScriptHex: mismatchCase.mismatchedLockingScriptHex
            )
            : validWalletParticipant
        let counterpartyParticipant = mismatchCase.side == .long
            ? Self.makeParticipantMaterial(
                from: validCounterpartyParticipant,
                lockingScriptHex: mismatchCase.mismatchedLockingScriptHex
            )
            : validCounterpartyParticipant
        let request = try HedgeFixtureData.betaRequest(
            walletParticipant: walletParticipant,
            counterpartyParticipant: counterpartyParticipant
        )

        #expect(throws: OpalBase.Hedge.Error.participantLockingScriptMismatch(mismatchCase.side)) {
            _ = try OpalBase.Hedge.buildOpalHedgePlan(from: request)
        }
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
        let expectedHash = try BroadcastHashExpectation.makeHash(from: broadcasts)
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

        let error = try await Self.captureAccountError {
            _ = try await plan.buildAndBroadcast(via: handler)
        }
        guard case .broadcastFailed = error else {
            throw AccountErrorCaptureFailure.unexpected(error)
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
            settlementTransactionHash: try HedgeFixtureData.settlementTransactionHash()
        )
        let reconstructedSummary = try OpalBase.Hedge.makeSettlementSummary(
            fundingDataDocumentJSON: result.fundingRecord.dataDocumentJSON,
            previousOracleProof: startingProof,
            settlementOracleProof: settlementProof,
            settlementTransactionHash: try HedgeFixtureData.settlementTransactionHash()
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

    enum AccountErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    private static let participantLockingScriptMismatchCases = [
        (side: OpalBase.Hedge.Side.hedge, mismatchedLockingScriptHex: HedgeFixtureData.longLockScriptHex),
        (side: OpalBase.Hedge.Side.long, mismatchedLockingScriptHex: HedgeFixtureData.shortLockScriptHex)
    ]

    private static func makeParticipantMaterial(
        from participant: OpalBase.Hedge.ParticipantMaterial,
        lockingScriptHex: String
    ) -> OpalBase.Hedge.ParticipantMaterial {
        OpalBase.Hedge.ParticipantMaterial(
            side: participant.side,
            payoutAddress: participant.payoutAddress,
            lockingScriptHex: lockingScriptHex,
            mutualRedeemPublicKeyHex: participant.mutualRedeemPublicKeyHex,
            derivedAddress: participant.derivedAddress
        )
    }

    private static func captureAccountError(
        _ work: () async throws -> Void
    ) async throws -> OpalBase.Account.Error {
        do {
            try await work()
            throw AccountErrorCaptureFailure.didNotThrow
        } catch let error as OpalBase.Account.Error {
            return error
        } catch let error as AccountErrorCaptureFailure {
            throw error
        } catch {
            throw AccountErrorCaptureFailure.unexpected(error)
        }
    }
}
