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
