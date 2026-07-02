// AccountReadOnlyRuntimeValidator+Validation.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

extension AccountReadOnlyRuntimeValidator {
    @Test(
        "read-only account validates descriptor and snapshot inputs",
        arguments: AccountReadOnlyRuntimeValidator.DescriptorValidationCase.allCases
    )
    func verifyReadOnlyAccountValidatesDescriptorAndSnapshotInputs(
        _ descriptorValidationCase: DescriptorValidationCase
    ) async throws {
        let privateAccount = try await AccountTestFixtures.makeAccount()
        let snapshot = await privateAccount.makeSnapshot()
        let accountOneSnapshot = await (try await AccountTestFixtures.makeAccount(unhardenedIndex: 1)).makeSnapshot()

        let invalidInput: (
            serializedAccountExtendedPublicKey: String,
            account: UInt32,
            snapshot: OpalBase.Account.Snapshot,
            expectedError: OpalBase.Account.Error
        )
        switch descriptorValidationCase {
        case .invalidSerializedAccountExtendedPublicKey:
            invalidInput = (
                serializedAccountExtendedPublicKey: "not-an-xpub",
                account: 0,
                snapshot: snapshot,
                expectedError: .invalidAccountExtendedPublicKey
            )
        case .rootExtendedPublicKey:
            invalidInput = (
                serializedAccountExtendedPublicKey: try Self.makeRootExtendedPublicKey(),
                account: 0,
                snapshot: snapshot,
                expectedError: .invalidAccountExtendedPublicKey
            )
        case .accountMismatch:
            invalidInput = (
                serializedAccountExtendedPublicKey: try Self.makeSerializedAccountExtendedPublicKey(account: 0),
                account: 1,
                snapshot: accountOneSnapshot,
                expectedError: .accountExtendedPublicKeyDoesNotMatchAccount
            )
        case .snapshotMismatch:
            invalidInput = (
                serializedAccountExtendedPublicKey: try Self.makeSerializedAccountExtendedPublicKey(account: 0),
                account: 0,
                snapshot: accountOneSnapshot,
                expectedError: .snapshotDoesNotMatchAccount
            )
        }

        await #expect(throws: invalidInput.expectedError) {
            _ = try await OpalBase.Account(
                serializedAccountExtendedPublicKey: invalidInput.serializedAccountExtendedPublicKey,
                purpose: .bip44,
                coinType: .bitcoinCash,
                account: invalidInput.account,
                snapshot: invalidInput.snapshot
            )
        }
    }

    @Test(
        "read-only account rejects private key required account paths",
        arguments: AccountReadOnlyRuntimeValidator.PrivateKeyRequiredOperationCase.allCases
    )
    func verifyReadOnlyAccountRejectsPrivateKeyRequiredPaths(
        _ privateKeyRequiredOperationCase: PrivateKeyRequiredOperationCase
    ) async throws {
        let privateAccount = try await AccountTestFixtures.makeAccount()
        let readOnlyAccount = try await Self.makeReadOnlyAccount(from: privateAccount)
        let tokenAwareAddress = try OpalBase.Address(AccountTestFixtures.tokenAwareAddressString)
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x72, count: 32)
        )
        let tokenData = OpalBase.CashTokens.TokenData(
            category: category,
            amount: 1,
            nft: nil
        )

        switch privateKeyRequiredOperationCase {
        case .bitcoinCashSpend:
            await #expect(throws: OpalBase.Account.Error.privateKeyMaterialUnavailable) {
                _ = try await readOnlyAccount.prepareSpend(
                    .init(recipients: [
                        .init(address: tokenAwareAddress, amount: try OpalBase.Satoshi(1_000))
                    ])
                )
            }
        case .tokenSpend:
            await #expect(throws: OpalBase.Account.Error.privateKeyMaterialUnavailable) {
                _ = try await readOnlyAccount.prepareTokenSpend(
                    .init(recipients: [
                        .init(address: tokenAwareAddress, amount: try OpalBase.Satoshi(1_000), tokenData: tokenData)
                    ])
                )
            }
        case .tokenGenesis:
            await #expect(throws: OpalBase.Account.Error.privateKeyMaterialUnavailable) {
                _ = try await readOnlyAccount.prepareTokenGenesis(
                    .init(recipients: [
                        .init(address: tokenAwareAddress, fungibleAmount: 1)
                    ])
                )
            }
        case .tokenMint:
            await #expect(throws: OpalBase.Account.Error.privateKeyMaterialUnavailable) {
                _ = try await readOnlyAccount.prepareTokenMint(
                    .init(
                        category: category,
                        recipients: [
                            .init(address: tokenAwareAddress, fungibleAmount: 1)
                        ]
                    )
                )
            }
        case .tokenCommitmentMutation:
            await #expect(throws: OpalBase.Account.Error.privateKeyMaterialUnavailable) {
                _ = try await readOnlyAccount.prepareTokenCommitmentMutation(
                    .init(
                        target: .preferredInput(Self.makeUnspentOutput(address: tokenAwareAddress, hashByte: 0x73)),
                        newCommitment: Data([0x01]),
                        destination: tokenAwareAddress
                    )
                )
            }
        case .cashFusionReservation:
        #if os(macOS)
            await #expect(throws: OpalBase.Account.Error.privateKeyMaterialUnavailable) {
                _ = try await readOnlyAccount.prepareCashFusionReservation(
                    request: .init(
                        selectedInputs: [
                            Self.makeUnspentOutput(
                                address: try await readOnlyAccount.selectNextDerivedAddress(for: .receiving).address,
                                value: 100_000,
                                hashByte: 0x74
                            )
                        ],
                        outputPolicy: .valuePreserving
                    )
                )
            }
        #else
            return
        #endif
        case .hedgeParticipantMaterial:
            await #expect(throws: OpalBase.Account.Error.privateKeyMaterialUnavailable) {
                _ = try await readOnlyAccount.reserveHedgeParticipantMaterial()
            }
            #expect((await readOnlyAccount.makeSnapshot()).addressBook.receivingEntries.allSatisfy { !$0.isReserved })
        case .hedgeFunding:
            let mismatchedWalletParticipant = Self.makeHedgeParticipantMaterial(
                from: try HedgeFixtureData.shortParticipant(),
                lockingScriptHex: HedgeFixtureData.longLockScriptHex
            )
            let request = try HedgeFixtureData.betaRequest(walletParticipant: mismatchedWalletParticipant)
            await #expect(throws: OpalBase.Account.Error.privateKeyMaterialUnavailable) {
                _ = try await readOnlyAccount.prepareHedgeFunding(request)
            }
        }
    }

    @Test("read-only account can prepare unsigned spend for external review")
    func readOnlyAccountCanPrepareUnsignedSpendForExternalReview() async throws {
        let privateAccount = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: privateAccount,
            value: 45_000,
            hashByte: 0x76
        )
        let readOnlyAccount = try await Self.makeReadOnlyAccount(from: privateAccount)
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.standardAddressString),
                    amount: try OpalBase.Satoshi(15_000)
                )
            ]
        )
        let authoring = OpalBase.WalletTransactionAuthoringInteractor(privateAccount: readOnlyAccount)

        let plan = try await authoring.prepareSpendForExternalReview(payment)

        #expect(plan.inputs == [selectedInput])
        #expect(plan.envelope.unsignedTransaction.inputs.count == 1)
        let unsignedInput = try #require(plan.envelope.unsignedTransaction.inputs.first)
        #expect(unsignedInput.unlockingScript.isEmpty == false)
        #expect(plan.envelope.spentOutputs.count == 1)
    }
}
