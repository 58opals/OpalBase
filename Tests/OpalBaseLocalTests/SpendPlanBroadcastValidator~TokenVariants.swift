// SpendPlanBroadcastValidator~TokenVariants.swift

import Foundation
import Testing
@testable import OpalBase

extension SpendPlanBroadcastValidator {
    @Test("token genesis buildAndBroadcast completes reservations on success")
    func tokenGenesisPlanBuildAndBroadcastCompletesReservationOnSuccess() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let genesisInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 70_000,
            hashByte: 0x78,
            outputIndex: 0
        )
        let genesis = try OpalBase.Account.TokenGenesis(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.tokenAwareAddressString),
                    fungibleAmount: 1
                )
            ]
        )
        let plan = try await account.prepareTokenGenesis(genesis, preferredGenesisInput: genesisInput)
        let expectedHash = AccountTestFixtures.makeHash(byte: 0x79)
        let handler = TransactionHandlingTestActor(
            broadcastResult: .success(expectedHash.reverseOrder.hexadecimalString)
        )

        let result = try await plan.buildAndBroadcast(via: handler)

        #expect(result.hash == expectedHash)
        #expect(result.result.category.transactionOrderData == genesisInput.previousTransactionHash.naturalOrder)
        #expect(!result.result.mintedOutputs.isEmpty)
        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
        let broadcasts = await handler.readBroadcastedTransactions()
        #expect(broadcasts.count == 1)
    }

    @Test("token genesis, mint, and mutation map domain-specific broadcast failures")
    func tokenPlanBroadcastFailuresMapDomainErrors() async throws {
        let failingHandler = TransactionHandlingTestActor(
            broadcastResult: .failure(NetworkStubError.forced("token-broadcast-failure"))
        )

        let genesisPlan = try await makeTokenGenesisPlan()
        do {
            _ = try await genesisPlan.buildAndBroadcast(via: failingHandler)
            Issue.record("Expected token genesis broadcast to throw")
        } catch let error as OpalBase.Account.Error {
            guard case .tokenGenesisBroadcastFailed = error else {
                Issue.record("Expected tokenGenesisBroadcastFailed but got \(error)")
                return
            }
        }
        try await genesisPlan.cancelReservation()

        let mintPlan = try await makeTokenMintPlan()
        do {
            _ = try await mintPlan.buildAndBroadcast(via: failingHandler)
            Issue.record("Expected token mint broadcast to throw")
        } catch let error as OpalBase.Account.Error {
            guard case .tokenMintBroadcastFailed = error else {
                Issue.record("Expected tokenMintBroadcastFailed but got \(error)")
                return
            }
        }
        try await mintPlan.cancelReservation()

        let mutationPlan = try await makeTokenMutationPlan()
        do {
            _ = try await mutationPlan.buildAndBroadcast(via: failingHandler)
            Issue.record("Expected token mutation broadcast to throw")
        } catch let error as OpalBase.Account.Error {
            guard case .tokenMutationBroadcastFailed = error else {
                Issue.record("Expected tokenMutationBroadcastFailed but got \(error)")
                return
            }
        }
        try await mutationPlan.cancelReservation()
    }
}

private extension SpendPlanBroadcastValidator {
    func makeTokenGenesisPlan() async throws -> OpalBase.Account.TokenGenesisPlan {
        let account = try await AccountTestFixtures.makeAccount()
        let genesisInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 70_000,
            hashByte: 0x81,
            outputIndex: 0
        )
        let genesis = try OpalBase.Account.TokenGenesis(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.tokenAwareAddressString),
                    fungibleAmount: 1
                )
            ]
        )
        return try await account.prepareTokenGenesis(genesis, preferredGenesisInput: genesisInput)
    }

    func makeTokenMintPlan() async throws -> OpalBase.Account.TokenMintPlan {
        let account = try await AccountTestFixtures.makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x82, count: 32))
        let mintingNonFungibleToken = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data([0x01]))
        let authorityToken = OpalBase.CashTokens.TokenData(category: category, amount: 10, nft: mintingNonFungibleToken)
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 20_000,
            tokenData: authorityToken,
            hashByte: 0x83
        )
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 100_000,
            hashByte: 0x84
        )
        let mint = try OpalBase.Account.TokenMint(
            category: category,
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.tokenAwareAddressString),
                    nft: try .init(capability: .none, commitment: Data([0x02]))
                )
            ]
        )
        return try await account.prepareTokenMint(mint)
    }

    func makeTokenMutationPlan() async throws -> OpalBase.Account.TokenCommitmentMutationPlan {
        let account = try await AccountTestFixtures.makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x85, count: 32))
        let mutableToken = try OpalBase.CashTokens.NFT(capability: .mutable, commitment: Data([0x03]))
        let authorityToken = OpalBase.CashTokens.TokenData(category: category, amount: 5, nft: mutableToken)
        let authorityInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 24_000,
            tokenData: authorityToken,
            hashByte: 0x86
        )
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 120_000,
            hashByte: 0x87
        )
        let mutation = try OpalBase.Account.TokenCommitmentMutation(
            target: .preferredInput(authorityInput),
            newCommitment: Data([0x04]),
            destination: try OpalBase.Address(AccountTestFixtures.tokenAwareAddressString)
        )
        return try await account.prepareTokenCommitmentMutation(mutation)
    }
}
