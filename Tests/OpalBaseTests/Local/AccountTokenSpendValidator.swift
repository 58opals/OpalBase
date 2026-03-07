// AccountTokenSpendValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("AccountActor Token Spend", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenSpendValidator {
    @Test("prepareTokenSpend builds a multi-category plan with token change")
    func prepareTokenSpendBuildsMultiCategoryPlanWithTokenChange() async throws {
        let account = try await makeAccount()
        let categoryAlpha = try CashTokensModel.CategoryIDModel(transactionOrderData: Data(repeating: 0xA1, count: 32))
        let categoryBeta = try CashTokensModel.CategoryIDModel(transactionOrderData: Data(repeating: 0xB2, count: 32))
        let nonFungibleToken = try CashTokensModel.NFTModel(capability: .none, commitment: Data([0x01]))
        let fungibleTokenDataAlpha = CashTokensModel.TokenData(category: categoryAlpha, amount: 100, nft: nil)
        let nonFungibleTokenDataAlpha = CashTokensModel.TokenData(category: categoryAlpha, amount: nil, nft: nonFungibleToken)
        let fungibleTokenDataBeta = CashTokensModel.TokenData(category: categoryBeta, amount: 50, nft: nil)
        
        let fungibleOutputAlpha = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: fungibleTokenDataAlpha,
            previousTransactionHash: TransactionModel.HashModel(naturalOrder: Data(repeating: 0x10, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let nonFungibleOutputAlpha = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: nonFungibleTokenDataAlpha,
            previousTransactionHash: TransactionModel.HashModel(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let fungibleOutputBeta = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: fungibleTokenDataBeta,
            previousTransactionHash: TransactionModel.HashModel(naturalOrder: Data(repeating: 0x12, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: TransactionModel.HashModel(naturalOrder: Data(repeating: 0x13, count: 32)),
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try AddressModel("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let recipients = [
            AccountActor.TokenTransferModel.Recipient(
                address: recipientAddress,
                amount: try SatoshiModel(1_000),
                tokenData: CashTokensModel.TokenData(category: categoryAlpha, amount: 40, nft: nil)
            ),
            AccountActor.TokenTransferModel.Recipient(
                address: recipientAddress,
                amount: try SatoshiModel(1_000),
                tokenData: CashTokensModel.TokenData(category: categoryAlpha, amount: nil, nft: nonFungibleToken)
            ),
            AccountActor.TokenTransferModel.Recipient(
                address: recipientAddress,
                amount: try SatoshiModel(1_000),
                tokenData: CashTokensModel.TokenData(category: categoryBeta, amount: 10, nft: nil)
            )
        ]
        
        let transfer = AccountActor.TokenTransferModel(recipients: recipients)
        let plan = try await account.prepareTokenSpend(transfer)
        
        let tokenInputCategories = Set(plan.tokenInputs.compactMap { $0.tokenData?.category })
        #expect(tokenInputCategories == Set([categoryAlpha, categoryBeta]))
        #expect(plan.tokenInputs.contains { $0.tokenData?.nft != nil && $0.tokenData?.category == categoryAlpha })
        #expect(plan.tokenInputs.contains { $0 == fungibleOutputAlpha })
        #expect(plan.tokenInputs.contains { $0 == nonFungibleOutputAlpha })
        #expect(plan.tokenInputs.contains { $0 == fungibleOutputBeta })
        
        var changeByCategory: [CashTokensModel.CategoryIDModel: CashTokensModel.TokenData] = .init()
        for output in plan.tokenChangeOutputs {
            let tokenData = try #require(output.tokenData)
            changeByCategory[tokenData.category] = tokenData
        }
        #expect(changeByCategory[categoryAlpha]?.amount == 60)
        #expect(changeByCategory[categoryBeta]?.amount == 40)
        
        _ = try plan.buildTransaction()
    }
}

private func makeAccount() async throws -> AccountActor {
    let mnemonic = try MnemonicModel(
        words: ["abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"]
    )
    let wallet = WalletActor(mnemonic: mnemonic)
    try await wallet.addAccount(unhardenedIndex: 0)
    return try await wallet.fetchAccount(at: 0)
}

private func addUnspentOutput(
    to account: AccountActor,
    value: UInt64,
    tokenData: CashTokensModel.TokenData?,
    previousTransactionHash: TransactionModel.HashModel,
    previousTransactionOutputIndex: UInt32
) async throws -> TransactionModel.OutputModel.UnspentModel {
    let addressBook = await account.addressBook
    let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
    let unspentOutput = TransactionModel.OutputModel.UnspentModel(
        value: value,
        lockingScript: receivingEntry.address.lockingScript.data,
        tokenData: tokenData,
        previousTransactionHash: previousTransactionHash,
        previousTransactionOutputIndex: previousTransactionOutputIndex
    )
    await addressBook.addUTXOs([unspentOutput])
    return unspentOutput
}

