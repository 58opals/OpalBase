import Foundation
import Testing
@testable import OpalBase

@Suite("Account Token Commitment Mutation", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenCommitmentMutationTests {
    @Test("mutates mutable non-fungible commitment and preserves fungible change externally")
    func testMutatesCommitmentAndPreservesFungibleChange() async throws {
        let account = try await makeAccount()
        let category = try CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xD1, count: 32))
        let mutableToken = try CashTokens.NFT(capability: .mutable, commitment: Data([0x01]))
        let authorityTokenData = CashTokens.TokenData(category: category, amount: 25, nft: mutableToken)
        let authorityOutput = try await addUnspentOutput(
            to: account,
            value: 25_000,
            tokenData: authorityTokenData,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x21, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x22, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let destinationAddress = try Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let mutation = try Account.TokenCommitmentMutation(
            target: .preferredInput(authorityOutput),
            newCommitment: Data([0x02]),
            destination: destinationAddress,
            preserveAttachedFungibleToWallet: true
        )
        
        let plan = try await account.prepareTokenCommitmentMutation(mutation)
        let mutatedTokenData = try #require(plan.mutatedTokenOutput.tokenData)
        let preservationOutput = try #require(plan.fungiblePreservationOutput)
        let preservationTokenData = try #require(preservationOutput.tokenData)
        
        #expect(plan.mutatedTokenOutput.lockingScript == destinationAddress.lockingScript.data)
        #expect(mutatedTokenData.amount == nil)
        #expect(mutatedTokenData.nft?.commitment == Data([0x02]))
        #expect(preservationTokenData.amount == 25)
        #expect(preservationTokenData.nft == nil)
        
        let addressBook = await account.addressBook
        let changeLockingScripts = await addressBook.listEntries(for: .change)
            .map { $0.address.lockingScript.data }
        #expect(changeLockingScripts.contains(preservationOutput.lockingScript))
    }
    
    @Test("accepts minting authority input for commitment mutation")
    func testAcceptsMintingAuthorityInput() async throws {
        let account = try await makeAccount()
        let category = try CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xD2, count: 32))
        let mintingToken = try CashTokens.NFT(capability: .minting, commitment: Data([0x03]))
        let authorityTokenData = CashTokens.TokenData(category: category, amount: 5, nft: mintingToken)
        let authorityOutput = try await addUnspentOutput(
            to: account,
            value: 22_000,
            tokenData: authorityTokenData,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x23, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 90_000,
            tokenData: nil,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x24, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
        let tokenAwareAddress = try Address(script: receivingEntry.address.lockingScript, format: .tokenAware)
        let mutation = try Account.TokenCommitmentMutation(
            target: .preferredInput(authorityOutput),
            newCommitment: Data([0x04]),
            destination: tokenAwareAddress
        )
        
        let plan = try await account.prepareTokenCommitmentMutation(mutation)
        let mutatedTokenData = try #require(plan.mutatedTokenOutput.tokenData)
        
        #expect(plan.authorityInput == authorityOutput)
        #expect(mutatedTokenData.nft?.capability == .minting)
        #expect(mutatedTokenData.nft?.commitment == Data([0x04]))
    }
    
    @Test("builds a transaction while respecting dust thresholds")
    func testBuildTransactionRespectsDustThresholds() async throws {
        let account = try await makeAccount()
        let category = try CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xD3, count: 32))
        let mutableToken = try CashTokens.NFT(capability: .mutable, commitment: Data([0x05]))
        let authorityTokenData = CashTokens.TokenData(category: category, amount: 12, nft: mutableToken)
        let authorityOutput = try await addUnspentOutput(
            to: account,
            value: 30_000,
            tokenData: authorityTokenData,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x25, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 150_000,
            tokenData: nil,
            previousTransactionHash: Transaction.Hash(naturalOrder: Data(repeating: 0x26, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let destinationAddress = try Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let mutation = try Account.TokenCommitmentMutation(
            target: .preferredInput(authorityOutput),
            newCommitment: Data([0x06]),
            destination: destinationAddress,
            preserveAttachedFungibleToWallet: true
        )
        
        let plan = try await account.prepareTokenCommitmentMutation(mutation)
        let transactionResult = try plan.buildTransaction()
        
        let mutatedDustThreshold = try plan.mutatedTokenOutput.dustThreshold(
            feeRate: Transaction.minimumRelayFeeRate
        )
        #expect(plan.mutatedTokenOutput.value >= mutatedDustThreshold)
        
        if let preservationOutput = plan.fungiblePreservationOutput {
            let preservationDustThreshold = try preservationOutput.dustThreshold(
                feeRate: Transaction.minimumRelayFeeRate
            )
            #expect(preservationOutput.value >= preservationDustThreshold)
        }
        
        #expect(!transactionResult.transaction.outputs.isEmpty)
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
