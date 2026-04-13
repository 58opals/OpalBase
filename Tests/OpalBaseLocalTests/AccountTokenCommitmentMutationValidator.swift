// AccountTokenCommitmentMutationValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account Token Commitment Mutation", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenCommitmentMutationValidator {
    @Test("mutates mutable non-fungible commitment and preserves fungible change externally")
    func mutatesCommitmentAndPreservesFungibleChange() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xD1, count: 32))
        let mutableToken = try OpalBase.CashTokens.NFT(capability: .mutable, commitment: Data([0x01]))
        let authorityTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 25, nft: mutableToken)
        let authorityOutput = try await addUnspentOutput(
            to: account,
            value: 25_000,
            tokenData: authorityTokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x21, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x22, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let destinationAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let mutation = try OpalBase.Account.TokenCommitmentMutation(
            target: .preferredInput(authorityOutput),
            newCommitment: Data([0x02]),
            destination: destinationAddress,
            shouldPreserveAttachedFungibleToWallet: true
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
        let changeLockingScripts = await addressBook.listEntries(for: OpalBase.Key.DerivationPath.Usage.change)
            .map { $0.address.lockingScript.data }
        #expect(changeLockingScripts.contains(preservationOutput.lockingScript))
    }
    
    @Test("accepts minting authority input for commitment mutation")
    func acceptsMintingAuthorityInput() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xD2, count: 32))
        let mintingToken = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data([0x03]))
        let authorityTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 5, nft: mintingToken)
        let authorityOutput = try await addUnspentOutput(
            to: account,
            value: 22_000,
            tokenData: authorityTokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x23, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 90_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x24, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: OpalBase.Key.DerivationPath.Usage.receiving)
        let tokenAwareAddress = try OpalBase.Address(script: receivingEntry.address.lockingScript, format: .tokenAware)
        let mutation = try OpalBase.Account.TokenCommitmentMutation(
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
    func buildTransactionRespectsDustThresholds() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xD3, count: 32))
        let mutableToken = try OpalBase.CashTokens.NFT(capability: .mutable, commitment: Data([0x05]))
        let authorityTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 12, nft: mutableToken)
        let authorityOutput = try await addUnspentOutput(
            to: account,
            value: 30_000,
            tokenData: authorityTokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x25, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 150_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x26, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let destinationAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let mutation = try OpalBase.Account.TokenCommitmentMutation(
            target: .preferredInput(authorityOutput),
            newCommitment: Data([0x06]),
            destination: destinationAddress,
            shouldPreserveAttachedFungibleToWallet: true
        )
        
        let plan = try await account.prepareTokenCommitmentMutation(mutation)
        let transactionResult = try plan.buildTransaction()
        
        let mutatedDustThreshold = try plan.mutatedTokenOutput.calculateDustThreshold(
            feeRate: OpalBase.Transaction.minimumRelayFeeRate
        )
        #expect(plan.mutatedTokenOutput.value >= mutatedDustThreshold)
        
        if let preservationOutput = plan.fungiblePreservationOutput {
            let preservationDustThreshold = try preservationOutput.calculateDustThreshold(
                feeRate: OpalBase.Transaction.minimumRelayFeeRate
            )
            #expect(preservationOutput.value >= preservationDustThreshold)
        }
        
        #expect(!transactionResult.transaction.outputs.isEmpty)
    }

    @Test("prepareTokenCommitmentMutation refreshes preserved fungible change when the selected change entry becomes stale")
    func prepareTokenCommitmentMutationRefreshesPreservedFungibleChangeWhenSelectedChangeEntryBecomesStale() async throws {
        let account = try await makeAccount()
        let addressBook = await account.addressBook
        let staleChangeEntry = try await addressBook.selectNextEntry(for: .change)
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xD4, count: 32))
        let mutableToken = try OpalBase.CashTokens.NFT(capability: .mutable, commitment: Data([0x07]))
        let authorityTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 25, nft: mutableToken)
        let authorityOutput = try await addUnspentOutput(
            to: account,
            value: 25_000,
            tokenData: authorityTokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x27, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let reservedFundingOutput = try await addUnspentOutput(
            to: account,
            value: 35_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x28, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x29, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let destinationAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let mutation = try OpalBase.Account.TokenCommitmentMutation(
            target: .preferredInput(authorityOutput),
            newCommitment: Data([0x08]),
            destination: destinationAddress,
            shouldPreserveAttachedFungibleToWallet: true
        )

        let plan = try await account.prepareTokenCommitmentMutation(
            mutation,
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
        let preservationOutput = try #require(plan.fungiblePreservationOutput)

        #expect(plan.bchChangeOutput.lockingScript != staleChangeEntry.address.lockingScript.data)
        #expect(preservationOutput.lockingScript == plan.bchChangeOutput.lockingScript)
        #expect(preservationOutput.lockingScript != staleChangeEntry.address.lockingScript.data)

        try await plan.cancelReservation()
        for reservation in await addressBook.readActiveSpendReservations() {
            try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
        }
    }
}

private func makeAccount() async throws -> OpalBase.Account {
    try await AccountTestFixtures.makeAccount()
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
