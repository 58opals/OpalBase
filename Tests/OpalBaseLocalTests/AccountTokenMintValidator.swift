// AccountTokenMintValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account Token Mint", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenMintValidator {
    @Test("uses minting authority input when minting non-fungible tokens")
    func usesAuthorityInputWhenMintingNonFungibleTokens() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xC1, count: 32))
        let mintingNonFungibleToken = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data([0x01]))
        let authorityTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 25, nft: mintingNonFungibleToken)
        let authorityOutput = try await addUnspentOutput(
            to: account,
            value: 20_000,
            tokenData: authorityTokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x10, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let recipients = [
            try OpalBase.Account.TokenMint.Recipient(
                address: recipientAddress,
                nft: OpalBase.CashTokens.NFT(capability: .none, commitment: Data([0x02]))
            ),
            try OpalBase.Account.TokenMint.Recipient(
                address: recipientAddress,
                nft: OpalBase.CashTokens.NFT(capability: .none, commitment: Data([0x03]))
            )
        ]
        let mint = try OpalBase.Account.TokenMint(category: category, recipients: recipients)
        
        let plan = try await account.prepareTokenMint(mint)
        
        #expect(plan.authorityInput == authorityOutput)
    }
    
    @Test("preserves fungible tokens on change when authority returns externally")
    func preservesFungibleTokensOnChangeWhenAuthorityReturnsExternally() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xC2, count: 32))
        let mintingNonFungibleToken = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data([0x04]))
        let authorityTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 40, nft: mintingNonFungibleToken)
        _ = try await addUnspentOutput(
            to: account,
            value: 25_000,
            tokenData: authorityTokenData,
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
        let externalAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let recipients = [
            try OpalBase.Account.TokenMint.Recipient(
                address: recipientAddress,
                nft: OpalBase.CashTokens.NFT(capability: .none, commitment: Data([0x05]))
            )
        ]
        let mint = try OpalBase.Account.TokenMint(
            category: category,
            recipients: recipients,
            authorityReturn: .toAddress(externalAddress)
        )
        
        let plan = try await account.prepareTokenMint(mint)
        let authorityReturnOutput = try #require(plan.authorityReturnOutput)
        let authorityReturnTokenData = try #require(authorityReturnOutput.tokenData)
        let preservationOutput = try #require(plan.fungiblePreservationOutput)
        let preservationTokenData = try #require(preservationOutput.tokenData)
        
        #expect(authorityReturnTokenData.amount == nil)
        #expect(authorityReturnTokenData.nft?.capability == .minting)
        #expect(preservationTokenData.amount == 40)
        #expect(preservationTokenData.nft == nil)
        #expect(preservationOutput.lockingScript != externalAddress.lockingScript.data)
        
        let addressBook = await account.addressBook
        let changeLockingScripts = await addressBook.listEntries(for: .change)
            .map { $0.address.lockingScript.data }
        #expect(changeLockingScripts.contains(preservationOutput.lockingScript))
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

