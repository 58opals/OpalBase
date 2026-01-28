import Foundation
import Testing
@testable import OpalBase

@Suite("Account Token Spend", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenSpendTests {
    @Test("prepareTokenSpend builds a multi-category plan with token change")
    func testPrepareTokenSpendBuildsMultiCategoryPlanWithTokenChange() async throws {
        let account = try await makeAccount()
        let categoryAlpha = try CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xA1, count: 32))
        let categoryBeta = try CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xB2, count: 32))
        let nonFungibleToken = try CashTokens.NFT(capability: .none, commitment: Data([0x01]))
        let fungibleTokenDataAlpha = CashTokens.TokenData(category: categoryAlpha, amount: 100, nft: nil)
        let nonFungibleTokenDataAlpha = CashTokens.TokenData(category: categoryAlpha, amount: nil, nft: nonFungibleToken)
        let fungibleTokenDataBeta = CashTokens.TokenData(category: categoryBeta, amount: 50, nft: nil)
        
        let fungibleOutputAlpha = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: fungibleTokenDataAlpha,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x10, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let nonFungibleOutputAlpha = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: nonFungibleTokenDataAlpha,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let fungibleOutputBeta = try await addUnspentOutput(
            to: account,
            value: 15_000,
            tokenData: fungibleTokenDataBeta,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x12, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x13, count: 32)),
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let recipients = [
            Account.TokenTransfer.Recipient(
                address: recipientAddress,
                amount: try Satoshi(1_000),
                tokenData: CashTokens.TokenData(category: categoryAlpha, amount: 40, nft: nil)
            ),
            Account.TokenTransfer.Recipient(
                address: recipientAddress,
                amount: try Satoshi(1_000),
                tokenData: CashTokens.TokenData(category: categoryAlpha, amount: nil, nft: nonFungibleToken)
            ),
            Account.TokenTransfer.Recipient(
                address: recipientAddress,
                amount: try Satoshi(1_000),
                tokenData: CashTokens.TokenData(category: categoryBeta, amount: 10, nft: nil)
            )
        ]
        
        let transfer = Account.TokenTransfer(recipients: recipients)
        let plan = try await account.prepareTokenSpend(transfer)
        
        let tokenInputCategories = Set(plan.tokenInputs.compactMap { $0.tokenData?.category })
        #expect(tokenInputCategories == Set([categoryAlpha, categoryBeta]))
        #expect(plan.tokenInputs.contains { $0.tokenData?.nft != nil && $0.tokenData?.category == categoryAlpha })
        #expect(plan.tokenInputs.contains { $0 == fungibleOutputAlpha })
        #expect(plan.tokenInputs.contains { $0 == nonFungibleOutputAlpha })
        #expect(plan.tokenInputs.contains { $0 == fungibleOutputBeta })
        
        var changeByCategory: [CashTokens.CategoryID: CashTokens.TokenData] = .init()
        for output in plan.tokenChangeOutputs {
            let tokenData = try #require(output.tokenData)
            changeByCategory[tokenData.category] = tokenData
        }
        #expect(changeByCategory[categoryAlpha]?.amount == 60)
        #expect(changeByCategory[categoryBeta]?.amount == 40)
        
        _ = try plan.buildTransaction()
    }
}

private func makeAccount() async throws -> Account {
    let mnemonic = try Mnemonic(
        words: ["abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"]
    )
    let wallet = Wallet(mnemonic: mnemonic)
    try await wallet.addAccount(unhardenedIndex: 0)
    return try await wallet.fetchAccount(at: 0)
}

private func addUnspentOutput(
    to account: Account,
    value: UInt64,
    tokenData: CashTokens.TokenData?,
    previousTransactionHash: Transaction.Hash,
    previousTransactionOutputIndex: UInt32
) async throws -> Transaction.Output.Unspent {
    let addressBook = await account.addressBook
    let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
    let unspentOutput = Transaction.Output.Unspent(
        value: value,
        lockingScript: receivingEntry.address.lockingScript.data,
        tokenData: tokenData,
        previousTransactionHash: previousTransactionHash,
        previousTransactionOutputIndex: previousTransactionOutputIndex
    )
    await addressBook.addUTXOs([unspentOutput])
    return unspentOutput
}
