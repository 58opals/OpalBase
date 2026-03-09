// AccountTokenSpendValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account Token Spend", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenSpendValidator {
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
        
        _ = try plan.buildTransaction()
    }
}

private func makeAccount() async throws -> OpalBase.Account {
    let mnemonic = try OpalBase.Mnemonic(
        words: ["abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"]
    )
    let wallet = OpalBase.Wallet(mnemonic: mnemonic)
    try await wallet.addAccount(unhardenedIndex: 0)
    return try await wallet.fetchAccount(at: 0)
}

private func addUnspentOutput(
    to account: OpalBase.Account,
    value: UInt64,
    tokenData: OpalBase.CashTokens.TokenData?,
    previousTransactionHash: OpalBase.Transaction.Hash,
    previousTransactionOutputIndex: UInt32
) async throws -> OpalBase.Transaction.Output.Unspent {
    let addressBook = await account.addressBook
    let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
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

