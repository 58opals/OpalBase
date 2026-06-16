// WalletTrustDomainInteractorValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Wallet trust-domain interactors", .tags(.unit, .wallet))
struct WalletTrustDomainInteractorValidator {
    @Test("descriptor blockchain sync refreshes public-chain state without secret authority")
    func descriptorBlockchainSyncRefreshesPublicChainStateWithoutSecretAuthority() async throws {
        let fixture = try await Self.makePublicDescriptorFixture()
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 14_000,
            lockingScript: fixture.receivingAddress.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x6a),
            previousTransactionOutputIndex: 0
        )
        let publicChain = OpalBase.WalletPublicChainOperations(
            addressReader: Self.makeAddressReader(
                unspentOutputsByAddress: [
                    fixture.receivingAddress.address.string: [unspentOutput]
                ]
            ),
            transactionClient: Self.makeTransactionClient()
        )
        let sync = try await OpalBase.WalletBlockchainSyncInteractor(
            accountDescriptor: fixture.descriptor,
            publicChain: publicChain
        )

        let refresh = try await sync.refreshUTXOSet(usage: .receiving)
        let snapshot = await sync.makeSnapshot()

        #expect(refresh.utxosByAddress[fixture.receivingAddress.address] == [unspentOutput])
        #expect(snapshot.addressBook.utxos.map(\.transactionHash) == [
            unspentOutput.previousTransactionHash.reverseOrder.hexadecimalString
        ])
    }

    @Test("receive address reservation is separate from blockchain sync")
    func receiveAddressReservationIsSeparateFromBlockchainSync() async throws {
        let fixture = try await Self.makePublicDescriptorFixture()
        let receiving = try await OpalBase.WalletReceiveAddressInteractor(
            accountDescriptor: fixture.descriptor
        )

        let reserved = try await receiving.reserveNextReceivingDerivedAddress()
        let snapshot = await receiving.makeSnapshot()

        #expect(reserved.derivationPath.usage == .receiving)
        #expect(snapshot.addressBook.receivingEntries.contains {
            $0.index == reserved.derivationPath.index && $0.isReserved
        })
    }

    @Test("transport adapter requires block header transport")
    func transportAdapterRequiresBlockHeaderTransport() async throws {
        let transportWithoutHeaders = OpalBase.WalletTransportInteractor(
            publicChain: .init(
                addressReader: Self.makeAddressReader(),
                transactionClient: Self.makeTransactionClient()
            )
        )
        let transportWithHeaders = OpalBase.WalletTransportInteractor(
            publicChain: .init(
                addressReader: Self.makeAddressReader(),
                transactionClient: Self.makeTransactionClient(),
                blockHeaderReader: Self.makeBlockHeaderReader()
            )
        )

        let adapterIsMissing: Bool
        if case nil = transportWithoutHeaders.makeWalletFulcrumAdapter() {
            adapterIsMissing = true
        } else {
            adapterIsMissing = false
        }
        #expect(adapterIsMissing)
        _ = try #require(transportWithHeaders.makeWalletFulcrumAdapter())

        let tipStreamIsMissing: Bool
        if case nil = try await transportWithoutHeaders.subscribeToTip() {
            tipStreamIsMissing = true
        } else {
            tipStreamIsMissing = false
        }
        #expect(tipStreamIsMissing)

        let tipStream = try await transportWithHeaders.subscribeToTip()
        _ = try #require(tipStream)
    }


    @Test("claimable interactor keeps claimable authoring domain-specific")
    func claimableInteractorKeepsClaimableAuthoringDomainSpecific() throws {
        let interactor = OpalBase.ClaimableInteractor()
        let refundPrivateKey = ClaimableTestSupport.makeClaimablePrivateKey(lastByte: 0x02)
        let draft = try interactor.makeDraft(
            network: .chipnet,
            refundPrivateKey: refundPrivateKey,
            expiryBlockHeight: 720
        )
        let fundingOutput = interactor.makeFundingOutput(from: draft, value: 25_000)
        let envelope = try interactor.makeEnvelope(
            contract: draft.contract,
            claimPrivateKey: draft.claimPrivateKey,
            fundingTransactionHash: AccountTestFixtures.makeHash(byte: 0x41),
            fundingOutputIndex: 0,
            fundingValue: fundingOutput.value
        )
        let shareCode = try interactor.encodeShareCode(for: envelope)
        let decodedEnvelope = try interactor.decodeShareCode(shareCode)
        let status = interactor.makeLocalStatus(for: decodedEnvelope, currentBlockHeight: 700)
        let claimTransaction = try interactor.buildClaimTransaction(
            from: decodedEnvelope,
            destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(),
            currentBlockHeight: 700
        )

        #expect(fundingOutput.lockingScript == draft.contract.fundingLockingScriptData)
        #expect(decodedEnvelope.contract == envelope.contract)
        #expect(status.allowsClaim)
        #expect(claimTransaction.inputs.count == 1)
        #expect(claimTransaction.outputs.count == 1)
    }

    @Test("public constructor labels expose trust-domain authority")
    func publicConstructorLabelsExposeTrustDomainAuthority() throws {
        let source = try WalletTrustDomainSourceFixture.readPublicInteractorSources()

        #expect(source.contains("struct WalletSnapshotInteractor"))
        #expect(source.contains("snapshotPersistence: OpalBase.Storage.SnapshotPersistence"))
        #expect(source.contains("struct WalletBlockchainSyncInteractor"))
        #expect(source.contains("accountDescriptor: OpalBase.WalletAccountPublicDescriptor"))
        #expect(source.contains("publicChain: OpalBase.WalletPublicChainOperations"))
        #expect(source.contains("struct WalletSecretAccessInteractor"))
        #expect(source.contains("persistenceSession: OpalBase.Storage.PersistenceSession"))
        #expect(source.contains("struct WalletTransactionAuthoringInteractor"))
        #expect(source.contains("privateAccount: OpalBase.Account"))
        #expect(source.contains("struct WalletBroadcastInteractor"))
        #expect(source.contains("transactionClient: OpalBase.Network.TransactionClient"))
        #expect(source.contains("struct ClaimableInteractor"))
        #expect(source.contains("makeFundingOutput"))
        #expect(source.contains("encodeShareCode"))
        #expect(source.contains("buildRefundTransaction"))
        #expect(source.contains("struct WalletObservabilityInteractor"))
    }

    @Test("snapshot DTO sources stay data-only")
    func snapshotDTOSourcesStayDataOnly() throws {
        let snapshotSource = try [
            WalletTrustDomainSourceFixture.readSourcePrefix(
                "Sources/OpalBase/Wallet/OpalBase+Wallet+Snapshot.swift",
                before: "extension _OpalBase.Wallet.Snapshot"
            ),
            WalletTrustDomainSourceFixture.readSourcePrefix(
                "Sources/OpalBase/Account/OpalBase+Account+Snapshot.swift",
                before: "extension _OpalBase.Account.Snapshot"
            )
        ].joined(separator: "\n")
        let forbiddenTerms = [
            "OpalBase.Network.",
            "AddressReader",
            "BlockHeaderReader",
            "TransactionClient",
            "Fulcrum.Client",
            "OpalBase.Key.Mnemonic",
            "SecureEnclave",
            "Keychain",
            "rootExtendedPrivateKey",
            "privateKey",
            "rawTransactionData",
            "rawTransactionHex"
        ]

        for term in forbiddenTerms {
            #expect(!snapshotSource.contains(term), "Snapshot DTO source should not contain \(term)")
        }
    }

    private static func makePublicDescriptorFixture() async throws -> (
        descriptor: OpalBase.WalletAccountPublicDescriptor,
        receivingAddress: OpalBase.Account.DerivedAddress
    ) {
        let privateAccount = try await AccountTestFixtures.makeAccount()
        let receivingAddress = try await privateAccount.selectNextDerivedAddress(for: .receiving)
        let snapshot = await privateAccount.makeSnapshot()
        let mnemonic = try OpalBase.Key.Mnemonic(
            phrase: AccountTestFixtures.mnemonicWords.joined(separator: " "),
            language: .english
        )
        let descriptor = try OpalBase.WalletAccountPublicDescriptor(
            serializedAccountExtendedPublicKey: mnemonic.makeSerializedAccountExtendedPublicKey(account: 0),
            purpose: .bip44,
            coinType: .bitcoinCash,
            accountUnhardenedIndex: 0,
            snapshot: snapshot
        )

        return (descriptor, receivingAddress)
    }

    private static func makeAddressReader(
        unspentOutputsByAddress: [String: [OpalBase.Transaction.Output.Unspent]] = [:]
    ) -> OpalBase.Network.AddressReader {
        OpalBase.Network.AddressReader(
            fetchBalance: { address, _ in
                .init(
                    confirmed: unspentOutputsByAddress[address, default: []].reduce(UInt64(0)) { $0 + $1.value },
                    unconfirmed: 0
                )
            },
            fetchUnspentOutputs: { address, _ in
                unspentOutputsByAddress[address, default: []]
            },
            fetchHistory: { _, _ in [] },
            fetchFirstUse: { _ in nil },
            fetchMempoolTransactions: { _ in [] },
            fetchScriptHash: { _ in "00" },
            subscribeToAddress: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )
    }

    private static func makeTransactionClient() -> OpalBase.Network.TransactionClient {
        OpalBase.Network.TransactionClient(
            broadcastTransaction: { _ in String(repeating: "0", count: 64) },
            fetchConfirmations: { _ in nil },
            fetchConfirmationStatus: { transactionHash in
                .init(
                    transactionHash: transactionHash,
                    transactionHeight: nil,
                    tipHeight: 0,
                    confirmations: nil
                )
            }
        )
    }

    private static func makeBlockHeaderReader() -> OpalBase.Network.BlockHeaderReader {
        OpalBase.Network.BlockHeaderReader(
            fetchTip: {
                .init(height: 1, headerHexadecimal: String(repeating: "0", count: 160))
            },
            subscribeToTip: {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )
    }

}
