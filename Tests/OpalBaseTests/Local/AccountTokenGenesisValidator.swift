import Foundation
import Testing
@testable import OpalBase

@Suite("AccountActor Token Genesis", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenGenesisValidator {
    @Test("rejects genesis input with non-zero output index")
    func rejectsGenesisInputWithNonZeroOutputIndex() async throws {
        let account = try await makeAccount()
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x11, count: 32))
        let unspentOutput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 1
        )
        
        let recipientAddress = try AddressModel("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let genesis = try AccountActor.TokenGenesisModel(recipients: [
            .init(address: recipientAddress, fungibleAmount: 1)
        ])
        
        await #expect(throws: AccountActor.Error.tokenGenesisInvalidGenesisInput) {
            _ = try await account.prepareTokenGenesis(genesis, preferredGenesisInput: unspentOutput)
        }
    }
    
    @Test("derives token category from genesis input hash")
    func derivesTokenCategoryFromGenesisInputHash() async throws {
        let account = try await makeAccount()
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x22, count: 32))
        let unspentOutput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try AddressModel("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let genesis = try AccountActor.TokenGenesisModel(recipients: [
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
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x33, count: 32))
        _ = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try AddressModel("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let genesis = try AccountActor.TokenGenesisModel(recipients: [
            .init(address: recipientAddress, fungibleAmount: 1)
        ])
        
        let plan = try await account.prepareTokenGenesis(genesis)
        let tokenOutput = try #require(plan.outputs.first { $0.tokenData != nil })
        let expectedDustOutput = TransactionModel.OutputModel(
            value: 0,
            address: recipientAddress,
            tokenData: tokenOutput.tokenData
        )
        let expectedDustThreshold = try expectedDustOutput.calculateDustThreshold(
            feeRate: TransactionModel.minimumRelayFeeRate
        )
        #expect(tokenOutput.value == expectedDustThreshold)
    }
    
    @Test("rejects non-token-aware genesis recipients")
    func rejectsNonTokenAwareRecipients() async throws {
        let account = try await makeAccount()
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x44, count: 32))
        let unspentOutput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let recipientAddress = try AddressModel("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let genesis = try AccountActor.TokenGenesisModel(recipients: [
            .init(address: recipientAddress, fungibleAmount: 1)
        ])
        
        await #expect(throws: AccountActor.Error.tokenGenesisRequiresTokenAwareAddress([recipientAddress])) {
            _ = try await account.prepareTokenGenesis(genesis, preferredGenesisInput: unspentOutput)
        }
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

private func addSpendableOutput(
    to account: AccountActor,
    previousTransactionHash: TransactionModel.HashModel,
    previousTransactionOutputIndex: UInt32,
    value: UInt64 = 50_000
) async throws -> TransactionModel.OutputModel.UnspentModel {
    let addressBook = await account.addressBook
    let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
    let unspentOutput = TransactionModel.OutputModel.UnspentModel(
        value: value,
        lockingScript: receivingEntry.address.lockingScript.data,
        previousTransactionHash: previousTransactionHash,
        previousTransactionOutputIndex: previousTransactionOutputIndex
    )
    await addressBook.addUTXOs([unspentOutput])
    return unspentOutput
}
