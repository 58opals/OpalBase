// StoragePersistenceNetworkSyncValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Storage persistence (OpalBase.Network)", .tags(.network))
struct StoragePersistenceNetworkSyncValidator {
    @Test("fulcrum sync updates account state, then persistence restores it", .timeLimit(.minutes(1)))
    func syncFulcrumPersistAndRestore() async throws {
        guard NetworkTestClient.isExtendedLiveNetworkEnabled else { return }
        let fulcrumURLFromEnv = ProcessInfo.processInfo.environment["OPAL_FULCRUM_URL"]
        let candidateServerStrings: [String] = [
            fulcrumURLFromEnv,
            "wss://bch.imaginary.cash:50004"
        ].compactMap { $0 }

        let candidateServers = candidateServerStrings.compactMap(URL.init(string:))
        guard !candidateServers.isEmpty else {
            Issue.record("No Fulcrum server URLs available (OPAL_FULCRUM_URL was empty and defaults could not be formed).")
            return
        }

        var lastConnectionError: Swift.Error?

        for url in candidateServers {
            let configuration = OpalBase.Network.Configuration(
                serverURLs: [url],
                connectionTimeout: .seconds(10),
                maximumMessageSize: 1024 * 1024,
                reconnect: .defaultValue,
                network: .mainnet
            )
            do {
                try await NetworkTestClient.withClient(configuration: configuration) { client in
                    let timeouts = OpalBase.Network.FulcrumRequestTimeoutModel(
                        headersTip: .seconds(10),
                        addressBalance: .seconds(10),
                        addressUnspent: .seconds(15),
                        addressHistory: .seconds(15)
                    )
                    let blockHeaderReader = OpalBase.Network.Fulcrum.BlockHeaderReader(client: client, timeouts: timeouts)
                    let addressReader = OpalBase.Network.Fulcrum.AddressReader(client: client, timeouts: timeouts)

                    let tip = try await blockHeaderReader.fetchTip()
                    #expect(tip.height > 0)
                    #expect(!tip.headerHexadecimal.isEmpty)

                    let mnemonic = try OpalBase.Mnemonic(length: .short, passphrase: "")
                    let wallet = OpalBase.Wallet(mnemonic: mnemonic)
                    try await wallet.addAccount(unhardenedIndex: 0)
                    let account = try await wallet.fetchAccount(at: 0)
                    let accountIdentifier = await account.id

                    let receivingAddress = try await account.reserveNextReceivingAddress()

                    var sawAddressInitialSnapshot = false
                    do {
                        let stream = try await addressReader.subscribeToAddress(receivingAddress.string)
                        for try await update in stream {
                            #expect(update.address == receivingAddress.string)
                            #expect(update.kind == .initialSnapshot)
                            if let status = update.status { #expect(!status.isEmpty) }
                            sawAddressInitialSnapshot = true
                            break
                        }
                    }
                    #expect(sawAddressInitialSnapshot == true)

                    var sawTipSnapshot = false
                    do {
                        let stream = try await blockHeaderReader.subscribeToTip()
                        for try await snapshot in stream {
                            #expect(snapshot.height > 0)
                            #expect(!snapshot.headerHexadecimal.isEmpty)
                            sawTipSnapshot = true
                            break
                        }
                    }
                    #expect(sawTipSnapshot == true)

                    let balance = try await addressReader.fetchBalance(for: receivingAddress.string, tokenFilter: .include)
                    #expect(balance.confirmed >= 0)
                    #expect(balance.unconfirmed >= 0)

                    let utxos = try await addressReader.fetchUnspentOutputs(for: receivingAddress.string, tokenFilter: .include)
                    let history = try await addressReader.fetchHistory(for: receivingAddress.string, includeUnconfirmed: true)

                    let fixedTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
                    let cachedBalance = try await account.replaceUTXOs(for: receivingAddress, with: utxos, timestamp: fixedTimestamp)
                    #expect(cachedBalance.balance.uint64 == utxos.reduce(0) { $0 + $1.value })

                    _ = try await account.refreshTransactionHistory(for: receivingAddress, using: addressReader, includeUnconfirmed: true)

                    let snapshotBeforePersist = await wallet.makeSnapshot()

                    let valueStore = OpalBase.Storage.ValueRepository.makeInMemory()
                    let storage = try OpalBase.Storage(valueStore: valueStore)
                    let mode = try await storage.persistState(for: wallet)
                    #expect([OpalBase.Storage.SecurityModel.ProtectionMode.plaintext, .software, .secureEnclave].contains(mode))

                    let restoredStorage = try OpalBase.Storage(valueStore: valueStore)
                    let session = OpalBase.Storage.PersistenceSessionModel(storage: restoredStorage)
                    let restored = try await session.restore(accountIdentifiers: [accountIdentifier])

                    guard let restoredWalletSnapshot = restored.walletSnapshot else {
                        Issue.record("Expected wallet snapshot after restore, but it was nil.")
                        return
                    }
                    #expect(restoredWalletSnapshot.words == snapshotBeforePersist.words)
                    #expect(restoredWalletSnapshot.passphrase == snapshotBeforePersist.passphrase)
                    #expect(restoredWalletSnapshot.accounts.count == snapshotBeforePersist.accounts.count)

                    guard let restoredAccountSnapshot = restored.accountSnapshots[accountIdentifier] else {
                        Issue.record("Expected restored account snapshot, but it was missing for the provided identifier.")
                        return
                    }
                    #expect(restoredAccountSnapshot.accountUnhardenedIndex == snapshotBeforePersist.accounts[0].accountUnhardenedIndex)

                    guard let restoredAddressBookSnapshot = restored.addressBookSnapshots[accountIdentifier] else {
                        Issue.record("Expected restored address book snapshot, but it was missing for the provided identifier.")
                        return
                    }

                    let restoredReceivingEntry = restoredAddressBookSnapshot.receivingEntries.first { $0.index == 0 }
                    #expect(restoredReceivingEntry != nil)
                    #expect(restoredReceivingEntry?.isReserved == true)

                    let restoredUtxoSum = restoredAddressBookSnapshot.utxos
                        .filter { $0.lockingScript == receivingAddress.lockingScript.data.hexadecimalString }
                        .reduce(0) { $0 + $1.value }
                    #expect(restoredUtxoSum == utxos.reduce(0) { $0 + $1.value })

                    let restoredTransactionHashes = Set(restoredAddressBookSnapshot.transactions.map { $0.transactionHash })
                    let serverTransactionHashes = Set(history.map { $0.transactionIdentifier.lowercased() })
                    #expect(serverTransactionHashes.isSubset(of: restoredTransactionHashes) || restoredTransactionHashes.isSubset(of: serverTransactionHashes))

                    if let restoredMnemonic = restored.mnemonic {
                        #expect(restoredMnemonic.words == snapshotBeforePersist.words)
                        #expect(restoredMnemonic.passphrase == snapshotBeforePersist.passphrase)
                        #expect(restored.mnemonicProtectionMode == mode)
                    } else {
                        #expect(restored.mnemonicProtectionMode == nil)
                    }
                }
                lastConnectionError = nil
                return
            } catch {
                lastConnectionError = error
            }
        }

        Issue.record("Failed to connect to any Fulcrum server. Last error: \(String(describing: lastConnectionError))")
    }
}

