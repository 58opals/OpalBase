// AccountTokenGenesisValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account Token Genesis", .tags(.unit, .wallet, .cashTokens))
struct AccountTokenGenesisValidator {
    @Test("reserved supply initializer normalizes sliced commitment")
    func reservedSupplyInitializerNormalizesSlicedCommitment() throws {
        let commitment = Data([0x01, 0x02, 0x03])
        let paddedCommitment = Data([0xff]) + commitment
        let slicedCommitment = paddedCommitment[paddedCommitment.index(after: paddedCommitment.startIndex)...]

        let reservedSupply = try OpalBase.Account.ReservedSupply(
            fungibleAmount: 1,
            shouldIncludeMintingNonFungibleToken: true,
            commitment: slicedCommitment
        )

        #expect(slicedCommitment.startIndex != commitment.startIndex)
        #expect(reservedSupply.commitment == commitment)
        #expect(reservedSupply.commitment.startIndex == commitment.startIndex)
    }

    @Test("token genesis recipients must include token data")
    func tokenGenesisRecipientsMustIncludeTokenData() throws {
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        
        #expect(throws: OpalBase.Account.Error.tokenGenesisRecipientHasNoTokenData) {
            _ = try OpalBase.Account.TokenGenesis.Recipient(address: recipientAddress)
        }
    }
    
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

    @Test("preferred genesis input uses stored UTXO metadata")
    func preferredGenesisInputUsesStoredUTXOMetadata() async throws {
        let account = try await makeAccount()
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x2A, count: 32))
        let storedInput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0,
            value: 50_000
        )
        let stalePreferredInput = OpalBase.Transaction.Output.Unspent(
            value: 90_000,
            lockingScript: storedInput.lockingScript,
            previousTransactionHash: storedInput.previousTransactionHash,
            previousTransactionOutputIndex: storedInput.previousTransactionOutputIndex
        )

        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let genesis = try OpalBase.Account.TokenGenesis(recipients: [
            .init(address: recipientAddress, fungibleAmount: 1)
        ])

        let plan = try await account.prepareTokenGenesis(genesis, preferredGenesisInput: stalePreferredInput)

        #expect(plan.genesisInput == storedInput)
        #expect(plan.genesisInput.value == storedInput.value)
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

    @Test("buildReview summarizes token genesis outputs and BCH accounting")
    func buildReviewSummarizesTokenGenesisOutputsAndBCHAccounting() async throws {
        let account = try await makeAccount()
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x66, count: 32))
        let genesisInput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0,
            value: 80_000
        )
        let nonFungibleToken = try OpalBase.CashTokens.NFT(
            capability: .mutable,
            commitment: Data([0xAB, 0xCD])
        )
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let genesis = try OpalBase.Account.TokenGenesis(recipients: [
            .init(
                address: recipientAddress,
                fungibleAmount: 42,
                nft: nonFungibleToken
            )
        ])

        let plan = try await account.prepareTokenGenesis(genesis, preferredGenesisInput: genesisInput)
        let review = try plan.buildReview()
        let mintedOutput = try #require(review.mintedOutputs.first)
        let expectedCategory = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: previousTransactionHash.naturalOrder
        )

        #expect(review.category == expectedCategory)
        #expect(review.category.hexForDisplay == previousTransactionHash.reverseOrder.hexadecimalString)
        #expect(review.rawTransactionByteCount == review.rawTransactionData.count)
        #expect(review.rawTransactionByteCount > 0)
        #expect(review.configuredFeeRate == plan.feeRate)
        #expect(review.effectiveFeeRate == Double(review.fee.uint64) / Double(review.rawTransactionByteCount))
        #expect(review.mintedOutputs.count == 1)
        #expect(mintedOutput.role == .minted)
        #expect(mintedOutput.category == expectedCategory)
        #expect(mintedOutput.fungibleAmount == 42)
        #expect(mintedOutput.nonFungibleTokenCapability == .mutable)
        #expect(mintedOutput.nonFungibleTokenCommitment == Data([0xAB, 0xCD]))
        let expectedLockedBCH = try OpalBase.Satoshi.sum(of: review.mintedOutputs) { $0.value }
        let expectedTotalBCHNeeded = try review.lockedBCHOutputValue + review.fee
        #expect(review.lockedBCHOutputValue == expectedLockedBCH)
        #expect(review.totalBCHNeeded == expectedTotalBCHNeeded)
        #expect(await account.addressBook.readActiveSpendReservations().count == 1)

        try await plan.cancelReservation()
        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
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

    @Test("prepareTokenGenesis refreshes reserved supply outputs when the selected change entry becomes stale")
    func prepareTokenGenesisRefreshesReservedSupplyOutputsWhenSelectedChangeEntryBecomesStale() async throws {
        let account = try await makeAccount()
        let addressBook = await account.addressBook
        let staleChangeEntry = try await addressBook.selectNextEntry(for: .change)
        let genesisInput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x55, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let reservedFundingOutput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x56, count: 32)),
            previousTransactionOutputIndex: 0,
            value: 35_000
        )
        _ = try await addSpendableOutput(
            to: account,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x57, count: 32)),
            previousTransactionOutputIndex: 0,
            value: 120_000
        )

        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let genesis = try OpalBase.Account.TokenGenesis(
            recipients: [.init(address: recipientAddress, fungibleAmount: 1)],
            reservedSupplyToSelf: .init(fungibleAmount: 77, shouldIncludeMintingNonFungibleToken: false)
        )

        let plan = try await account.prepareTokenGenesis(
            genesis,
            preferredGenesisInput: genesisInput,
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

        let transactionResult = try plan.buildTransaction()
        let reservedSupplyOutput = try #require(transactionResult.mintedOutputs.first(where: {
            $0.tokenData?.amount == 77
        }))
        let bchChange = try #require(transactionResult.bchChange)
        #expect(bchChange.derivedAddress.address.lockingScript.data != staleChangeEntry.address.lockingScript.data)
        #expect(reservedSupplyOutput.lockingScript == bchChange.derivedAddress.address.lockingScript.data)
        #expect(reservedSupplyOutput.lockingScript != staleChangeEntry.address.lockingScript.data)

        try await plan.cancelReservation()
        for reservation in await addressBook.readActiveSpendReservations() {
            try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
        }
    }

    @Test("BCH funding selection excludes the token genesis input")
    func bchFundingSelectionExcludesTokenGenesisInput() async throws {
        let account = try await makeAccount()
        let addressBook = await account.addressBook
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let genesisInput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x58, count: 32)),
            previousTransactionOutputIndex: 0,
            value: 1_000
        )
        let fundingInput = try await addSpendableOutput(
            to: account,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x59, count: 32)),
            previousTransactionOutputIndex: 0,
            value: 800
        )
        let recipientAddress = try OpalBase.Address("bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w")
        let output = OpalBase.Transaction.Output(value: 1_300, address: recipientAddress, tokenData: nil)

        let selected = try await account.selectBCHInputs(
            from: [genesisInput, fundingInput],
            existingInputs: [genesisInput],
            outputs: [output],
            feeRate: 1,
            shouldAllowDustDonation: true,
            changeLockingScript: changeEntry.address.lockingScript.data
        )

        #expect(selected == [fundingInput])
    }

    @Test("token genesis outpoint preparation rejects dust outputs")
    func prepareTokenGenesisOutpointRejectsDustOutputs() async throws {
        let account = try await makeAccount()
        let destinationAddress = try OpalBase.Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let outputTemplate = OpalBase.Transaction.Output(value: 0, address: destinationAddress)
        let estimatedFee = try OpalBase.Transaction.estimateFee(
            inputCount: 1,
            outputs: [outputTemplate],
            feePerByte: OpalBase.Transaction.minimumRelayFeeRate
        )
        let dustThreshold = try outputTemplate.calculateDustThreshold(
            feeRate: OpalBase.Transaction.minimumRelayFeeRate
        )
        _ = try await addSpendableOutput(
            to: account,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x5A, count: 32)),
            previousTransactionOutputIndex: 1,
            value: estimatedFee + dustThreshold - 1
        )

        await #expect(throws: OpalBase.Account.Error.tokenGenesisInvalidGenesisInput) {
            _ = try await account.prepareTokenGenesisOutpoint()
        }
        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
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
        let receivingEntry = try await addressBook.selectNextEntry(for: OpalBase.Key.DerivationPath.Usage.receiving)
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: value,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: previousTransactionOutputIndex
        )
        await addressBook.addUTXOs([unspentOutput])
        return unspentOutput
    }
}
