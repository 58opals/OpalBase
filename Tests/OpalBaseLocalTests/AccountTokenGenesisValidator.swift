// AccountTokenGenesisValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account Token Genesis", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenGenesisValidator {
    @Test("rejects genesis input with non-zero output index")
    func rejectsGenesisInputWithNonZeroOutputIndex() async throws {
        let account = try await makeAccount()
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let unspentOutput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )
        
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let genesis = try OpalBase.Account.TokenGenesis(recipients: [
            .init(address: recipientAddress, fungibleAmount: 1)
        ])
        
        await #expect(throws: OpalBase.Account.Error.tokenGenesisInvalidGenesisInput) {
            _ = try await account.prepareTokenGenesis(genesis, preferredGenesisInput: unspentOutput)
        }
    }
    
    @Test("derives token category from genesis input hash")
    func derivesTokenCategoryFromGenesisInputHash() async throws {
        let account = try await makeAccount()
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x22, count: 32))
        let unspentOutput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let genesis = try OpalBase.Account.TokenGenesis(recipients: [
            .init(address: recipientAddress, fungibleAmount: 1)
        ])
        
        let plan = try await account.prepareTokenGenesis(genesis, preferredGenesisInput: unspentOutput)
        let result = try plan.buildTransaction()
        #expect(!result.mintedOutputs.isEmpty)
        
        let expectedDisplayHex = previousTransactionHash.reverseOrder.hexadecimalString
        for output in result.mintedOutputs {
            let tokenData = try #require(output.tokenData)
            #expect(tokenData.category.transactionOrderData == previousTransactionHash.naturalOrder)
            #expect(tokenData.category.hexForDisplay == expectedDisplayHex)
        }
    }
    
    @Test("uses dust threshold when genesis recipient lacks BCH amount")
    func usesDustThresholdWhenRecipientAmountIsNil() async throws {
        let account = try await makeAccount()
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x33, count: 32))
        _ = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let genesis = try OpalBase.Account.TokenGenesis(recipients: [
            .init(address: recipientAddress, fungibleAmount: 1)
        ])
        
        let plan = try await account.prepareTokenGenesis(genesis)
        let tokenOutput = try #require(plan.outputs.first { $0.tokenData != nil })
        let expectedDustOutput = OpalBase.Transaction.Output(
            value: 0,
            address: recipientAddress,
            tokenData: tokenOutput.tokenData
        )
        let expectedDustThreshold = try expectedDustOutput.calculateDustThreshold(
            feeRate: OpalBase.Transaction.minimumRelayFeeRate
        )
        #expect(tokenOutput.value == expectedDustThreshold)
    }
    
    @Test("rejects non-token-aware genesis recipients")
    func rejectsNonTokenAwareRecipients() async throws {
        let account = try await makeAccount()
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x44, count: 32))
        let unspentOutput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try OpalBase.Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let genesis = try OpalBase.Account.TokenGenesis(recipients: [
            .init(address: recipientAddress, fungibleAmount: 1)
        ])
        
        await #expect(throws: OpalBase.Account.Error.tokenGenesisRequiresTokenAwareAddress([recipientAddress])) {
            _ = try await account.prepareTokenGenesis(genesis, preferredGenesisInput: unspentOutput)
        }
    }
}

private func makeAccount() async throws -> OpalBase.Account {
    try await AccountTestFixtures.makeAccount()
}

private func addSpendableOutput(
    to account: OpalBase.Account,
    previousTransactionHash: OpalBase.Transaction.Hash,
    previousTransactionOutputIndex: UInt32,
    value: UInt64 = 50_000
) async throws -> OpalBase.Transaction.Output.Unspent {
    let addressBook = await account.addressBook
    let receivingEntry = try await addressBook.selectNextEntry(for: OpalBase.DerivationPath.Usage.receiving)
    let unspentOutput = OpalBase.Transaction.Output.Unspent(
        value: value,
        lockingScript: receivingEntry.address.lockingScript.data,
        previousTransactionHash: previousTransactionHash,
        previousTransactionOutputIndex: previousTransactionOutputIndex
    )
    await addressBook.addUTXOs([unspentOutput])
    return unspentOutput
}
