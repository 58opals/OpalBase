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
        let changeLockingScripts = await addressBook.listEntries(for: OpalBase.Key.DerivationPath.Usage.change)
            .map { $0.address.lockingScript.data }
        #expect(changeLockingScripts.contains(preservationOutput.lockingScript))
    }

    @Test("prepareTokenMint rejects dust recipient overrides before reservation")
    func prepareTokenMintRejectsDustRecipientOverridesBeforeReservation() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xC3, count: 32))
        let mintingNonFungibleToken = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data([0x06]))
        let authorityTokenData = OpalBase.CashTokens.TokenData(category: category, amount: nil, nft: mintingNonFungibleToken)
        _ = try await addUnspentOutput(
            to: account,
            value: 25_000,
            tokenData: authorityTokenData,
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
        let mint = try OpalBase.Account.TokenMint(
            category: category,
            recipients: [
                try .init(
                    address: recipientAddress,
                    bchAmount: try OpalBase.Satoshi(1),
                    nft: OpalBase.CashTokens.NFT(capability: .none, commitment: Data([0x07]))
                )
            ]
        )

        await #expect(
            throws: OpalBase.Account.Error.transactionBuildFailed(
                OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit
            )
        ) {
            _ = try await account.prepareTokenMint(mint)
        }

        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("preferred minting input uses stored UTXO metadata")
    func preferredMintingInputUsesStoredUTXOMetadata() async throws {
        let account = try await makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xD1, count: 32))
        let storedInput = try await addUnspentOutput(
            to: account,
            value: 25_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0xD2, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let staleMintingToken = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data([0x01]))
        let stalePreferredInput = OpalBase.Transaction.Output.Unspent(
            value: storedInput.value,
            lockingScript: storedInput.lockingScript,
            tokenData: OpalBase.CashTokens.TokenData(category: category, amount: nil, nft: staleMintingToken),
            previousTransactionHash: storedInput.previousTransactionHash,
            previousTransactionOutputIndex: storedInput.previousTransactionOutputIndex
        )
        _ = try await addUnspentOutput(
            to: account,
            value: 120_000,
            tokenData: nil,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0xD3, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let mint = try OpalBase.Account.TokenMint(
            category: category,
            recipients: [
                try .init(
                    address: recipientAddress,
                    nft: OpalBase.CashTokens.NFT(capability: .none, commitment: Data([0x02]))
                )
            ]
        )

        await #expect(throws: OpalBase.Account.Error.tokenMintNoEligibleMintingInput) {
            _ = try await account.prepareTokenMint(mint, preferredMintingInput: stalePreferredInput)
        }
        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await account.addressBook.listSpendableUTXOs().contains(storedInput))
    }

    @Test("prepareTokenMint refreshes wallet-owned token outputs when the selected change entry becomes stale")
    func prepareTokenMintRefreshesWalletOwnedTokenOutputsWhenSelectedChangeEntryBecomesStale() async throws {
        let account = try await makeAccount()
        let addressBook = await account.addressBook
        let staleChangeEntry = try await addressBook.selectNextEntry(for: .change)
        let reservedFundingOutput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 35_000,
            hashByte: 0x47
        )
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0xC4, count: 32))
        let mintingNonFungibleToken = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data([0x09]))
        let authorityTokenData = OpalBase.CashTokens.TokenData(category: category, amount: 40, nft: mintingNonFungibleToken)
        _ = try await addUnspentOutput(
            to: account,
            value: 25_000,
            tokenData: authorityTokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x48, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 120_000,
            hashByte: 0x49
        )

        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let externalAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let mint = try OpalBase.Account.TokenMint(
            category: category,
            recipients: [
                try .init(
                    address: recipientAddress,
                    nft: OpalBase.CashTokens.NFT(capability: .none, commitment: Data([0x0A]))
                )
            ],
            authorityReturn: .toAddress(externalAddress)
        )

        let plan = try await account.prepareTokenMint(
            mint,
            preferredMintingInput: nil,
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
        #expect(preservationOutput.lockingScript != externalAddress.lockingScript.data)

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
