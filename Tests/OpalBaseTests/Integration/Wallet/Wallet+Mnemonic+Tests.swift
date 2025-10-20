import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet Mnemonic Integration", .tags(.integration, .network, .fulcrum))
struct WalletMnemonicIntegrationSuite {
    private static let mnemonicWords: [String] = [
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "abandon",
        "about"
    ]
    
    private static let expectedReceivingAddress = "bitcoincash:qqyx49mu0kkn9ftfj6hje6g2wfer34yfnq5tahq3q6"
    private static let balanceVerificationSampleSize = 5
    
    private static func makeSeededWalletAndAccount(endpoint: String) async throws -> (Wallet, Account) {
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        return (wallet, account)
    }
    
    @Test("derives the receiving address from the mnemonic using Fulcrum")
    func derivesReceivingAddressFromMnemonic() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        let entry = try await account.addressBook.selectNextEntry(for: .receiving)
        
        #expect(entry.address.string == Self.expectedReceivingAddress)
    }
    
    @Test("restores mnemonic wallets and syncs with Fulcrum", .tags(.integration, .network, .fulcrum))
    func restoresMnemonicWalletsAndSyncsWithFulcrum() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        
        let mnemonicWords = Self.mnemonicWords
        let mnemonic = try Mnemonic(words: mnemonicWords)
        let walletA = Wallet(mnemonic: mnemonic)
        let walletB = Wallet(mnemonic: try Mnemonic(words: mnemonicWords))
        
        try await walletA.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        try await walletB.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let accountA = try await walletA.fetchAccount(at: 0)
        let accountB = try await walletB.fetchAccount(at: 0)
        
        let receivingEntryA = try await accountA.addressBook.selectNextEntry(for: .receiving)
        let receivingEntryB = try await accountB.addressBook.selectNextEntry(for: .receiving)
        let changeEntryA = try await accountA.addressBook.selectNextEntry(for: .change)
        let changeEntryB = try await accountB.addressBook.selectNextEntry(for: .change)
        
        let accountIDA = await accountA.id
        let accountIDB = await accountB.id
        
        #expect(accountIDA == accountIDB)
        #expect(receivingEntryA.address.string == receivingEntryB.address.string)
        #expect(changeEntryA.address.string == changeEntryB.address.string)
        
        _ = try await walletA.calculateBalance()
        _ = try await walletB.calculateBalance()
    }
    
    @Test("restores wallet snapshot without changing derivations", .tags(.integration, .network, .fulcrum))
    func restoresWalletSnapshotWithoutChangingDerivations() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        let addressBook = await account.addressBook
        
        let originalReceivingAddresses = await addressBook
            .listEntries(for: .receiving)
            .map { $0.address.string }
        let originalChangeAddresses = await addressBook
            .listEntries(for: .change)
            .map { $0.address.string }
        
        let snapshot = await wallet.makeSnapshot()
        let restored = try await Wallet(from: snapshot)
        let restoredAccount = try await restored.fetchAccount(at: 0)
        let restoredAddressBook = await restoredAccount.addressBook
        
        let restoredReceivingAddresses = await restoredAddressBook
            .listEntries(for: .receiving)
            .map { $0.address.string }
        let restoredChangeAddresses = await restoredAddressBook
            .listEntries(for: .change)
            .map { $0.address.string }
        
        let hasSameNumberOfAccounts = await restored.numberOfAccounts == wallet.numberOfAccounts
        
        #expect(hasSameNumberOfAccounts)
        #expect(restoredReceivingAddresses == originalReceivingAddresses)
        #expect(restoredChangeAddresses == originalChangeAddresses)
    }
    
    @Test("reports consistent balances between aggregate and sampled entries", .tags(.integration, .network, .fulcrum))
    func reportsConsistentBalancesBetweenAggregateAndSampledEntries() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        
        let aggregateBalance = try await account.calculateBalance()
        
        let connectionPool = await account.fulcrumPool
        let node = try await connectionPool.acquireNode()
        let addressBook = await account.addressBook
        
        let receivingSampleSize = 5
        let receivingEntries = await addressBook.listEntries(for: .receiving)
        let sampledEntries = receivingEntries.prefix(receivingSampleSize)
        
        var sampledTotal: UInt64 = 0
        for entry in sampledEntries {
            let balance = try await addressBook.fetchBalance(for: entry.address, using: node)
            sampledTotal &+= balance.uint64
        }
        
        let aggregateValue = aggregateBalance.uint64
        let delta = aggregateValue > sampledTotal ? aggregateValue - sampledTotal : sampledTotal - aggregateValue
        
        #expect(delta <= 1, "Aggregate balance diverges from sampled entry balances by more than a satoshi.")
    }
    
    @Test("verifies aggregate balance consistency with Fulcrum", .tags(.integration, .network, .fulcrum))
    func verifiesAggregateBalanceConsistencyWithFulcrum() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        
        let (_, account) = try await Self.makeSeededWalletAndAccount(endpoint: endpoint)
        
        let aggregateBalance = try await account.calculateBalance()
        let node = try await account.fulcrumPool.acquireNode()
        let addressBook = await account.addressBook
        let receivingEntries = await addressBook.listEntries(for: .receiving)
        let sampledEntries = receivingEntries.prefix(Self.balanceVerificationSampleSize)
        
        var summedBalance = Satoshi()
        for entry in sampledEntries {
            let entryBalance = try await addressBook.fetchBalance(for: entry.address, using: node)
            summedBalance = try summedBalance + entryBalance
        }
        
        let aggregateValue = aggregateBalance.uint64
        let sampledValue = summedBalance.uint64
        let difference = aggregateValue > sampledValue ? aggregateValue - sampledValue : sampledValue - aggregateValue
        
        #expect(difference <= 1,
                "Aggregate balance \(aggregateValue) and sampled balance \(sampledValue) differ by more than one satoshi")
    }
    
    @Test("builds raw transaction from live UTXOs - v1", .tags(.integration, .network, .fulcrum, .transaction))
    func buildsRawTransactionFromLiveUTXOs1() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        guard let recipientAddress = Environment.sendAddress,
              let targetAmount = Environment.sendAmount
        else { return }
        
        let (_, account) = try await Self.makeSeededWalletAndAccount(endpoint: endpoint)
        
        try await account.refreshUTXOSet()
        
        let availableUTXOs = await account.addressBook.listUTXOs()
        #expect(!availableUTXOs.isEmpty, "Live funding is required to build a transaction")
        
        let recipientOutput = Transaction.Output(value: targetAmount.uint64, address: recipientAddress)
        let changeEntry = try await account.addressBook.selectNextEntry(for: .change, fetchBalance: false)
        
        let selectedUTXOs = try await account.addressBook.selectUTXOs(
            targetAmount: targetAmount,
            recipientOutputs: [recipientOutput],
            changeLockingScript: changeEntry.address.lockingScript.data,
            feePerByte: Transaction.defaultFeeRate,
            strategy: .greedyLargestFirst
        )
        
        let spendableTotal = selectedUTXOs.reduce(into: UInt64(0)) { partial, utxo in
            partial &+= utxo.value
        }
        
        #expect(spendableTotal >= targetAmount.uint64)
        
        let privateKeys = try await account.addressBook.derivePrivateKeys(for: selectedUTXOs)
        let tentativeChangeValue = spendableTotal &- targetAmount.uint64
        let changeOutput = Transaction.Output(value: tentativeChangeValue, address: changeEntry.address)
        
        let transaction = try Transaction.build(
            utxoPrivateKeyPairs: privateKeys,
            recipientOutputs: [recipientOutput],
            changeOutput: changeOutput,
            feePerByte: Transaction.defaultFeeRate
        )
        
        let encoded = transaction.encode()
        #expect(!encoded.isEmpty)
        
        let matchingRecipientOutputs = transaction.outputs.filter { output in
            output.lockingScript == recipientAddress.lockingScript.data && output.value == targetAmount.uint64
        }
        #expect(matchingRecipientOutputs.count == 1)
        
        let expectedChangeScript = changeEntry.address.lockingScript.data
        let changeOutputs = transaction.outputs.filter { $0.lockingScript == expectedChangeScript }
        #expect(!changeOutputs.isEmpty)
        
        if let actualChange = changeOutputs.first {
            let calculatedFee = transaction.calculateFee(feePerByte: Transaction.defaultFeeRate)
            let expectedChangeValue = spendableTotal &- targetAmount.uint64 &- calculatedFee
            #expect(actualChange.value == expectedChangeValue)
        }
        
        let transactionHash = Transaction.Hash(naturalOrder: HASH256.hash(encoded))
        #expect(transactionHash.naturalOrder.count == 32)
    }
    
    @Test("builds raw transaction from live UTXOs - v2", .tags(.integration, .network, .fulcrum, .transaction))
    func buildsRawTransactionFromLiveUTXOs2() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        guard let recipientAddress = Environment.sendAddress,
              let sendAmount = Environment.sendAmount else { return }
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        let accountIndex = UInt32(clamping: Environment.getTestBalanceAccountIndex())
        for index in UInt32(0)...accountIndex {
            try await wallet.addAccount(unhardenedIndex: index, fulcrumServerURLs: [endpoint])
        }
        
        let account = try await wallet.fetchAccount(at: accountIndex)
        
        try await account.refreshUTXOSet()
        let refreshedUTXOs = await account.addressBook.listUTXOs()
        #expect(!refreshedUTXOs.isEmpty)
        
        let recipientOutput = Transaction.Output(value: sendAmount.uint64, address: recipientAddress)
        let changeEntry = try await account.addressBook.selectNextEntry(for: .change, fetchBalance: false)
        
        let selectedUTXOs = try await account.addressBook.selectUTXOs(
            targetAmount: sendAmount,
            recipientOutputs: [recipientOutput],
            changeLockingScript: changeEntry.address.lockingScript.data,
            feePerByte: Transaction.defaultFeeRate,
            strategy: .greedyLargestFirst
        )
        #expect(!selectedUTXOs.isEmpty)
        
        let privateKeys = try await account.addressBook.derivePrivateKeys(for: selectedUTXOs)
        
        let spendableValue = selectedUTXOs.reduce(into: UInt64(0)) { partialResult, utxo in
            partialResult &+= utxo.value
        }
        #expect(spendableValue > sendAmount.uint64)
        
        let changeFundingValue = spendableValue - sendAmount.uint64
        let changeOutput = Transaction.Output(value: changeFundingValue, address: changeEntry.address)
        
        let transaction = try Transaction.build(
            utxoPrivateKeyPairs: privateKeys,
            recipientOutputs: [recipientOutput],
            changeOutput: changeOutput,
            feePerByte: Transaction.defaultFeeRate
        )
        
        let encodedTransaction = transaction.encode()
        #expect(!encodedTransaction.isEmpty)
        
        let outputs = transaction.outputs
        let matchingRecipientOutputs = outputs.filter { output in
            output.value == recipientOutput.value && output.lockingScript == recipientOutput.lockingScript
        }
        #expect(matchingRecipientOutputs.count == 1)
        
        let expectedChangeScript = changeEntry.address.lockingScript.data
        let matchingChangeOutputs = outputs.filter { $0.lockingScript == expectedChangeScript }
        #expect(matchingChangeOutputs.count == 1)
        
        let expectedHashData = HASH256.hash(encodedTransaction)
        let manualTransactionHash = Transaction.Hash(naturalOrder: expectedHashData)
        #expect(manualTransactionHash.naturalOrder == expectedHashData)
    }
    
    @Test("builds raw transaction from live UTXOs - v3", .tags(.integration, .network, .fulcrum, .transaction))
    func buildsRawTransactionFromLiveUTXOs3() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        guard let recipientAddress = Environment.sendAddress,
              let targetAmount = Environment.sendAmount
        else { return }
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        let accountIndex = UInt32(clamping: Environment.getTestBalanceAccountIndex())
        for index in UInt32(0)...accountIndex {
            try await wallet.addAccount(unhardenedIndex: index, fulcrumServerURLs: [endpoint])
        }
        
        let account = try await wallet.fetchAccount(at: accountIndex)
        
        try await account.refreshUTXOSet()
        
        let refreshedUTXOs = await account.addressBook.listUTXOs()
        #expect(!refreshedUTXOs.isEmpty, "Live transaction requires funded UTXO set.")
        
        let changeEntry = try await account.addressBook.selectNextEntry(for: .change, fetchBalance: false)
        
        let recipientOutput = Transaction.Output(value: targetAmount.uint64, address: recipientAddress)
        
        let selectedUTXOs = try await account.addressBook.selectUTXOs(
            targetAmount: targetAmount,
            recipientOutputs: [recipientOutput],
            changeLockingScript: changeEntry.address.lockingScript.data,
            feePerByte: Transaction.defaultFeeRate,
            strategy: .greedyLargestFirst
        )
        
        #expect(!selectedUTXOs.isEmpty, "Coin selection must choose spendable UTXOs.")
        
        let selectedTotal = selectedUTXOs.reduce(into: UInt64(0)) { partial, utxo in
            partial &+= utxo.value
        }
        
        #expect(selectedTotal >= targetAmount.uint64, "Selected UTXOs do not cover requested amount.")
        
        let changePlaceholderValue = selectedTotal &- targetAmount.uint64
        #expect(changePlaceholderValue > Transaction.dustLimit,
                "Selected UTXOs should leave dust-free change for the transaction.")
        
        let changeOutput = Transaction.Output(value: changePlaceholderValue, address: changeEntry.address)
        
        let utxoPrivateKeyPairs = try await account.addressBook.derivePrivateKeys(for: selectedUTXOs)
        
        #expect(utxoPrivateKeyPairs.count == selectedUTXOs.count,
                "Each selected UTXO must map to a private key for signing.")
        
        let transaction = try Transaction.build(
            utxoPrivateKeyPairs: utxoPrivateKeyPairs,
            recipientOutputs: [recipientOutput],
            changeOutput: changeOutput,
            feePerByte: Transaction.defaultFeeRate
        )
        
        let encodedTransaction = transaction.encode()
        #expect(!encodedTransaction.isEmpty, "Encoded transaction should not be empty.")
        
        #expect(transaction.inputs.count == selectedUTXOs.count,
                "Transaction should include all selected inputs.")
        
        let recipientMatches = transaction.outputs.filter { output in
            output.value == recipientOutput.value && output.lockingScript == recipientOutput.lockingScript
        }
        #expect(recipientMatches.count == 1, "Transaction must include exactly one recipient output.")
        
        let changeScript = changeEntry.address.lockingScript.data
        let changeMatches = transaction.outputs.filter { $0.lockingScript == changeScript }
        #expect(changeMatches.count == 1, "Transaction should contain a change output for the next change address.")
        
        if let producedChange = changeMatches.first {
            #expect(producedChange.value <= changePlaceholderValue,
                    "Change output should not exceed leftover input value.")
            #expect(producedChange.value >= Transaction.dustLimit,
                    "Change output must be above dust after fees are applied.")
        }
        
        let totalOutputs = transaction.outputs.reduce(into: UInt64(0)) { partial, output in
            partial &+= output.value
        }
        let feePaid = selectedTotal &- totalOutputs
        #expect(feePaid > 0, "Transaction should reserve a positive miner fee.")
        
        let hashedTransaction = HASH256.hash(encodedTransaction)
        let transactionHash = Transaction.Hash(naturalOrder: hashedTransaction)
        #expect(transactionHash.naturalOrder == hashedTransaction,
                "Transaction hash should reflect the double-SHA256 digest of the encoded transaction.")
        #expect(transactionHash.naturalOrder.count == 32,
                "Transaction hash must be 32 bytes in natural order.")
    }
    
    @Test("builds raw transaction from live UTXOs - v4", .tags(.integration, .network, .fulcrum, .transaction))
    func buildsRawTransactionFromLiveUTXOs4() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        guard let recipient = Environment.sendAddress,
              let amount = Environment.sendAmount
        else { return }
        
        let (_, account) = try await Self.makeSeededWalletAndAccount(endpoint: endpoint)
        
        try await account.refreshUTXOSet()
        
        let addressBook = await account.addressBook
        let refreshedUTXOs = await addressBook.listUTXOs()
        
        #expect(!refreshedUTXOs.isEmpty, "A funded account is required to assemble a transaction.")
        
        let recipientOutput = Transaction.Output(value: amount.uint64, address: recipient)
        let changeEntry = try await addressBook.selectNextEntry(for: .change, fetchBalance: false)
        let changeScript = changeEntry.address.lockingScript.data
        
        let selectedUTXOs = try await addressBook.selectUTXOs(
            targetAmount: amount,
            recipientOutputs: [recipientOutput],
            changeLockingScript: changeScript,
            feePerByte: Transaction.defaultFeeRate,
            strategy: .greedyLargestFirst
        )
        
        #expect(!selectedUTXOs.isEmpty)
        
        let selectedTotal = selectedUTXOs.reduce(into: UInt64(0)) { partial, utxo in
            partial &+= utxo.value
        }
        #expect(selectedTotal >= amount.uint64)
        
        let privateKeys = try await addressBook.derivePrivateKeys(for: selectedUTXOs)
        
        let changeCandidateValue = selectedTotal &- amount.uint64
        #expect(changeCandidateValue > Transaction.dustLimit)
        let changeOutput = Transaction.Output(value: changeCandidateValue, address: changeEntry.address)
        
        let transaction = try Transaction.build(version: 2,
                                                utxoPrivateKeyPairs: privateKeys,
                                                recipientOutputs: [recipientOutput],
                                                changeOutput: changeOutput,
                                                feePerByte: Transaction.defaultFeeRate)
        
        let encoded = transaction.encode()
        #expect(!encoded.isEmpty)
        
        let recipientMatches = transaction.outputs.filter { output in
            output.lockingScript == recipient.lockingScript.data
        }
        #expect(recipientMatches.count == 1)
        #expect(recipientMatches.first?.value == amount.uint64)
        
        let changeMatches = transaction.outputs.filter { output in
            output.lockingScript == changeScript
        }
        #expect(changeMatches.count == 1)
        
        guard let transactionChange = changeMatches.first else {
            #expect(Bool(false), "Transaction is missing the expected change output.")
            return
        }
        
        let totalOutputValue = transaction.outputs.reduce(into: UInt64(0)) { partial, output in
            partial &+= output.value
        }
        #expect(totalOutputValue >= amount.uint64)
        #expect(transactionChange.value == totalOutputValue &- amount.uint64)
        
        let paidFee = selectedTotal &- totalOutputValue
        #expect(paidFee > 0)
        
        let manualHash = Transaction.Hash(naturalOrder: HASH256.hash(encoded))
        let reconstructedHash = Transaction.Hash(reverseOrder: manualHash.reverseOrder)
        #expect(manualHash == reconstructedHash)
    }
    
    @Test("matches Fulcrum balance with refreshed UTXO set", .tags(.integration, .network, .fulcrum))
    func matchesFulcrumBalanceWithRefreshedUTXOSet() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        
        let mnemonic = try Mnemonic(words: Self.mnemonicWords)
        let wallet = Wallet(mnemonic: mnemonic)
        
        let accountIndex = UInt32(clamping: Environment.getTestBalanceAccountIndex())
        
        for index in UInt32(0)...accountIndex {
            try await wallet.addAccount(unhardenedIndex: index, fulcrumServerURLs: [endpoint])
        }
        
        let account = try await wallet.fetchAccount(at: accountIndex)
        
        try await account.refreshUTXOSet()
        
        let utxos = await account.addressBook.listUTXOs()
        let summedValue = utxos.reduce(into: UInt64(0)) { partial, utxo in
            partial &+= utxo.value
        }
        let summed = try Satoshi(summedValue)
        
        let calculated = try await account.calculateBalance()
        
        #expect(calculated == summed)
        
        if let firstReceiving = await account.addressBook.listEntries(for: .receiving).first?.address {
            let node = try await account.fulcrumPool.acquireNode()
            let perAddressValue = utxos.reduce(into: UInt64(0)) { partial, utxo in
                if utxo.lockingScript == firstReceiving.lockingScript.data {
                    partial &+= utxo.value
                }
            }
            let perAddressBalance = try Satoshi(perAddressValue)
            let remoteBalance = try await node.balance(for: firstReceiving, includeUnconfirmed: true)
            
            #expect(perAddressBalance == remoteBalance)
        }
    }
}
