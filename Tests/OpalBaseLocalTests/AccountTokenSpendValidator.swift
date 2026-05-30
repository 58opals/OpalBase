// AccountTokenSpendValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account Token Spend", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenSpendValidator {
    @Test("token input selection ignores fungible tokens from other categories")
    func tokenInputSelectionIgnoresFungibleTokensFromOtherCategories() async throws {
        let account = try await makeAccount()
        let requestedCategory = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xA1, count: 32))
        let otherCategory = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xB2, count: 32))
        let wrongCategoryOutput = makeTokenUnspentOutput(
            category: otherCategory,
            amount: 100,
            previousTransactionByte: 0x10
        )
        let requestedCategoryOutput = makeTokenUnspentOutput(
            category: requestedCategory,
            amount: 20,
            previousTransactionByte: 0x11
        )
        let requirements = OpalBase.Account.TokenRequirements(
            category: requestedCategory,
            fungibleAmount: 10,
            nonFungibleTokens: .init()
        )

        let selected = try await account.selectTokenInputs(
            from: [wrongCategoryOutput, requestedCategoryOutput],
            requirements: requirements
        )

        #expect(selected == [requestedCategoryOutput])
    }

    @Test("token input selection prefers pure fungible outputs before unrelated NFTs")
    func tokenInputSelectionPrefersPureFungibleOutputsBeforeUnrelatedNFTs() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xA2, count: 32))
        let unrelatedNonFungibleToken = try OpalBase.CashTokens.NFT(capability: .none, commitment: Data([0x01]))
        let nonFungibleOutput = makeTokenUnspentOutput(
            category: category,
            amount: 100,
            nonFungibleToken: unrelatedNonFungibleToken,
            previousTransactionByte: 0x12
        )
        let pureFungibleOutput = makeTokenUnspentOutput(
            category: category,
            amount: 50,
            previousTransactionByte: 0x13
        )
        let requirements = OpalBase.Account.TokenRequirements(
            category: category,
            fungibleAmount: 40,
            nonFungibleTokens: .init()
        )

        let selected = try await account.selectTokenInputs(
            from: [nonFungibleOutput, pureFungibleOutput],
            requirements: requirements
        )

        #expect(selected == [pureFungibleOutput])
    }

    @Test("token inventory ignores fungible tokens from other categories")
    func tokenInventoryIgnoresFungibleTokensFromOtherCategories() async throws {
        let account = try await makeAccount()
        let requestedCategory = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xA1, count: 32))
        let otherCategory = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xB2, count: 32))
        let requestedCategoryOutput = makeTokenUnspentOutput(
            category: requestedCategory,
            amount: 20,
            previousTransactionByte: 0x11
        )
        let otherCategoryOutput = makeTokenUnspentOutput(
            category: otherCategory,
            amount: 100,
            previousTransactionByte: 0x12
        )

        let inventory = try await account.makeTokenInventory(
            from: [requestedCategoryOutput, otherCategoryOutput],
            category: requestedCategory
        )

        #expect(inventory.fungibleAmount == 20)
        #expect(inventory.nonFungibleTokens.isEmpty)
    }

    @Test("prepareTokenSpend builds a multi-category plan with token change")
    func prepareTokenSpendBuildsMultiCategoryPlanWithTokenChange() async throws {
        let account = try await makeAccount()
        let categoryAlpha = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xA1, count: 32))
        let categoryBeta = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xB2, count: 32))
        let nonFungibleToken = try OpalBase.CashTokens.NFT(capability: .none, commitment: Data([0x01]))
        let fungibleTokenDataAlpha = OpalBase.CashTokens.TokenData(category: categoryAlpha, amount: 100, nft: nil)
        let nonFungibleTokenDataAlpha = OpalBase.CashTokens.TokenData(category: categoryAlpha, amount: nil, nft: nonFungibleToken)
        let fungibleTokenDataBeta = OpalBase.CashTokens.TokenData(category: categoryBeta, amount: 50, nft: nil)
        
        let fungibleOutputAlpha = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: fungibleTokenDataAlpha,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x10, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let nonFungibleOutputAlpha = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: nonFungibleTokenDataAlpha,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let fungibleOutputBeta = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: fungibleTokenDataBeta,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x12, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x13, count: 32)),
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let recipients = [
            OpalBase.Account.TokenTransfer.Recipient(
                address: recipientAddress,
                amount: try OpalBase.Satoshi(1_000),
                tokenData: OpalBase.CashTokens.TokenData(category: categoryAlpha, amount: 40, nft: nil)
            ),
            OpalBase.Account.TokenTransfer.Recipient(
                address: recipientAddress,
                amount: try OpalBase.Satoshi(1_000),
                tokenData: OpalBase.CashTokens.TokenData(category: categoryAlpha, amount: nil, nft: nonFungibleToken)
            ),
            OpalBase.Account.TokenTransfer.Recipient(
                address: recipientAddress,
                amount: try OpalBase.Satoshi(1_000),
                tokenData: OpalBase.CashTokens.TokenData(category: categoryBeta, amount: 10, nft: nil)
            )
        ]
        
        let transfer = OpalBase.Account.TokenTransfer(recipients: recipients)
        let plan = try await account.prepareTokenSpend(transfer)
        let review = try plan.buildReview()
        
        let tokenInputCategories = Set(plan.tokenInputs.compactMap { $0.tokenData?.category })
        #expect(tokenInputCategories == Set([categoryAlpha, categoryBeta]))
        #expect(plan.tokenInputs.contains { $0.tokenData?.nft != nil && $0.tokenData?.category == categoryAlpha })
        #expect(plan.tokenInputs.contains { $0 == fungibleOutputAlpha })
        #expect(plan.tokenInputs.contains { $0 == nonFungibleOutputAlpha })
        #expect(plan.tokenInputs.contains { $0 == fungibleOutputBeta })
        
        var changeByCategory: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.TokenData] = .init()
        for output in plan.tokenChangeOutputs {
            let tokenData = try #require(output.tokenData)
            changeByCategory[tokenData.category] = tokenData
        }
        #expect(changeByCategory[categoryAlpha]?.amount == 60)
        #expect(changeByCategory[categoryBeta]?.amount == 40)
        
        #expect(review.rawTransactionByteCount == review.rawTransactionData.count)
        #expect(review.rawTransactionByteCount > 0)
        #expect(review.configuredFeeRate == plan.feeRate)
        #expect(review.effectiveFeeRate == Double(review.fee.uint64) / Double(review.rawTransactionByteCount))
        #expect(review.tokenRecipientOutputs.count == recipients.count)
        #expect(review.tokenRecipientOutputs.allSatisfy { $0.role == .recipient })
        #expect(review.tokenChangeOutputs.allSatisfy { $0.role == .tokenChange })
        #expect(review.tokenRecipientOutputs.map(\.category) == recipients.map { Optional($0.tokenData.category) })
        #expect(review.tokenRecipientOutputs.map(\.fungibleAmount) == recipients.map { $0.tokenData.amount })
        let reviewedNonFungibleOutput = try #require(review.tokenRecipientOutputs.first {
            $0.nonFungibleTokenCommitment == nonFungibleToken.commitment
        })
        #expect(reviewedNonFungibleOutput.nonFungibleTokenCapability == Optional(OpalBase.CashTokens.NFT.Capability.none))
        #expect(reviewedNonFungibleOutput.category == categoryAlpha)
        let reviewedTokenChangeByCategory = Dictionary(
            uniqueKeysWithValues: review.tokenChangeOutputs.compactMap { output in
                output.category.map { ($0, output) }
            }
        )
        #expect(reviewedTokenChangeByCategory[categoryAlpha]?.fungibleAmount == 60)
        #expect(reviewedTokenChangeByCategory[categoryBeta]?.fungibleAmount == 40)
        let selectedBCH = try OpalBase.Satoshi.sum(
            of: plan.tokenInputs + plan.bchInputs
        ) { try OpalBase.Satoshi($0.value) }
        let outputBCH = try OpalBase.Satoshi.sum(
            of: review.transaction.outputs
        ) { try OpalBase.Satoshi($0.value) }
        #expect(try selectedBCH - outputBCH == review.fee)
        let expectedLockedBCH = try OpalBase.Satoshi.sum(
            of: review.tokenRecipientOutputs + review.tokenChangeOutputs
        ) { $0.value }
        #expect(review.lockedBCHOutputValue == expectedLockedBCH)
        #expect(await account.addressBook.readActiveSpendReservations().count == 1)

        try await plan.cancelReservation()
        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("prepareTokenSpend rejects invalid token recipient data before reservation")
    func prepareTokenSpendRejectsInvalidTokenRecipientDataBeforeReservation() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xA3, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 20, nft: nil)
        _ = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: tokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x14, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x15, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let transfer = OpalBase.Account.TokenTransfer(recipients: [
            .init(
                address: recipientAddress,
                amount: try OpalBase.Satoshi(1_000),
                tokenData: OpalBase.CashTokens.TokenData(category: category, amount: 10, nft: nil)
            ),
            .init(
                address: recipientAddress,
                amount: try OpalBase.Satoshi(1_000),
                tokenData: OpalBase.CashTokens.TokenData(category: category, amount: 0, nft: nil)
            )
        ])

        await #expect(
            throws: OpalBase.Account.Error.tokenTransferInvalidTokenData(
                OpalBase.CashTokens.Error.invalidTokenPrefixFungibleAmount
            )
        ) {
            _ = try await account.prepareTokenSpend(transfer)
        }

        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("prepareTokenSpend rejects dust token recipients before reservation")
    func prepareTokenSpendRejectsDustTokenRecipientsBeforeReservation() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xA4, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 20, nft: nil)
        _ = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: tokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x16, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x17, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let transfer = OpalBase.Account.TokenTransfer(recipients: [
            .init(
                address: recipientAddress,
                amount: try OpalBase.Satoshi(1),
                tokenData: OpalBase.CashTokens.TokenData(category: category, amount: 10, nft: nil)
            )
        ])

        await #expect(
            throws: OpalBase.Account.Error.tokenSelectionFailed(
                OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit
            )
        ) {
            _ = try await account.prepareTokenSpend(transfer)
        }

        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("prepareTokenSpend refreshes wallet token change when the selected change entry becomes stale")
    func prepareTokenSpendRefreshesWalletTokenChangeWhenSelectedChangeEntryBecomesStale() async throws {
        let account = try await makeAccount()
        let addressBook = await account.addressBook
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xC3, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 100, nft: nil)
        _ = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: tokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x21, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let reservedFundingOutput = try await addUnspentOutput(
            to: account,
            value: 30_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x22, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x23, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let staleChangeEntry = try await addressBook.selectNextEntry(for: .change)

        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let transfer = OpalBase.Account.TokenTransfer(recipients: [
            .init(
                address: recipientAddress,
                amount: try OpalBase.Satoshi(1_000),
                tokenData: OpalBase.CashTokens.TokenData(category: category, amount: 40, nft: nil)
            )
        ])

        let plan = try await account.prepareTokenSpend(
            transfer,
            feePolicy: .init(),
            beforeReservation: { selectedChangeEntry in
                #expect(selectedChangeEntry.address == staleChangeEntry.address)
                _ = try await addressBook.reserveSpend(
                    utxos: [reservedFundingOutput],
                    changeEntry: selectedChangeEntry,
                    tokenSelectionPolicy: .excludeTokenUTXOs
                )
            }
        )

        #expect(!plan.tokenChangeOutputs.isEmpty)
        #expect(plan.bchChangeOutput.lockingScript != staleChangeEntry.address.lockingScript.data)
        #expect(plan.tokenChangeOutputs.allSatisfy { $0.lockingScript == plan.bchChangeOutput.lockingScript })
        #expect(plan.tokenChangeOutputs.allSatisfy { $0.lockingScript != staleChangeEntry.address.lockingScript.data })

        try await plan.cancelReservation()
        for reservation in await addressBook.readActiveSpendReservations() {
            try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
        }
    }
}

private func makeAccount() async throws -> OpalBase.Account {
    try await AccountTestFixtures.makeAccount()
}

private func makeTokenUnspentOutput(
    category: OpalBase.CashTokens.CategoryID,
    amount: UInt64,
    nonFungibleToken: OpalBase.CashTokens.NFT? = nil,
    previousTransactionByte: UInt8
) -> OpalBase.Transaction.Output.Unspent {
    OpalBase.Transaction.Output.Unspent(
        value: 15_000,
        lockingScript: Data([0x51]),
        tokenData: OpalBase.CashTokens.TokenData(category: category, amount: amount, nft: nonFungibleToken),
        previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: previousTransactionByte, count: 32)),
        previousTransactionOutputIndex: 0
    )
}

private func addUnspentOutput(
    to account: OpalBase.Account,
    value: UInt64,
    tokenData: OpalBase.CashTokens.TokenData?,
    previousTransactionHash: OpalBase.Transaction.Hash,
    previousTransactionOutputIndex: UInt32
) async throws -> OpalBase.Transaction.Output.Unspent {
    let addressBook = await account.addressBook
    let receivingEntry = try await addressBook.selectNextEntry(for: OpalBase.Key.DerivationPath.Usage.receiving)
    let unspentOutput = OpalBase.Transaction.Output.Unspent(
        value: value,
        lockingScript: receivingEntry.address.lockingScript.data,
        tokenData: tokenData,
        previousTransactionHash: previousTransactionHash,
        previousTransactionOutputIndex: previousTransactionOutputIndex
    )
    await addressBook.addUTXOs([unspentOutput])
    return unspentOutput
}
