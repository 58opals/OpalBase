import Foundation
import SwiftFulcrum

extension Address {
    struct Book {
        private var extendedKey: PrivateKey.Extended
        private var addressToPrivateKey = [Address: PrivateKey]()
        
        private var receiving = [Entry]()
        private var change = [Entry]()
        
        private var utxos = Set<Transaction.Output.Unspent>()
        
        var fulcrum: Fulcrum
        
        private let gapLimit = 20
        private let maxIndex = UInt32.max
        
        init(extendedKey: PrivateKey.Extended, fulcrum: Fulcrum) async throws {
            self.extendedKey = extendedKey
            self.fulcrum = fulcrum
            
            try await generateInitialAddresses()
            try await syncUTXOSet()
        }
        
        struct Entry {
            let usage: DerivationPath.Usage
            let address: Address
            var isUsed: Bool
            var cache: Cache
        }
    }
}

// MARK: - Entry
extension Address.Book {
    private func getEntries(of usage: DerivationPath.Usage) -> [Entry] {
        switch usage {
        case .receiving:
            return receiving
        case .change:
            return change
        }
    }
    
    private func findEntry(for address: Address) -> Entry? {
        return (receiving + change).first(where: { $0.address == address })
    }
}

// MARK: - UTXO
extension Address.Book {
    mutating func addUTXO(_ utxo: Transaction.Output.Unspent) {
        self.utxos.insert(utxo)
    }
    
    mutating func addUTXOs(_ utxos: [Transaction.Output.Unspent]) {
        self.utxos.formUnion(utxos)
    }
    
    mutating func removeUTXO(_ utxo: Transaction.Output.Unspent) {
        self.utxos.remove(utxo)
    }
    
    mutating func removeUTXOs(_ utxos: [Transaction.Output.Unspent]) {
        self.utxos.subtract(utxos)
    }
    
    mutating func clearUTXOs() {
        self.utxos.removeAll()
    }
    
    func getUTXOs() -> Set<Transaction.Output.Unspent> {
        return utxos
    }
    
    func selectUTXOs(targetAmount: Satoshi,
                     feePerByte: UInt64 = 1) throws -> [Transaction.Output.Unspent] {
        var selectedUTXOs: [Transaction.Output.Unspent] = []
        var totalAmount: UInt64 = 0
        let sortedUTXOs = utxos.sorted { $0.value > $1.value }
        
        for utxo in sortedUTXOs {
            selectedUTXOs.append(utxo)
            totalAmount += utxo.value
            
            let estimatedTransactionSize = selectedUTXOs.count * 148 + 34 + 10
            let estimatedFee = UInt64(estimatedTransactionSize) * feePerByte
            
            if totalAmount >= targetAmount.uint64 + (estimatedFee*2) {
                return selectedUTXOs
            }
        }
        
        throw Error.insufficientFunds
    }
    
    mutating func syncUTXOSet() async throws {
        var updatedUTXOs = [Transaction.Output.Unspent]()
        
        for entry in (receiving + change) {
            let newUTXOs = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
            let newUTXOsWithTheCorrectlyOrderedPreviousTransactionHash = newUTXOs.map {
                Transaction.Output.Unspent(value: $0.value,
                                           lockingScript: $0.lockingScript,
                                           previousTransactionHash: $0.previousTransactionHash,
                                           previousTransactionOutputIndex: $0.previousTransactionOutputIndex)
            }
            updatedUTXOs.append(contentsOf: newUTXOsWithTheCorrectlyOrderedPreviousTransactionHash)
        }
        
        clearUTXOs()
        addUTXOs(updatedUTXOs)
    }
}

// MARK: - Address: Generating
extension Address.Book {
    private mutating func generateInitialAddresses() async throws {
        try await generateAddresses(for: .receiving, numberOfNewEntries: gapLimit)
        try await generateAddresses(for: .change, numberOfNewEntries: gapLimit)
    }
    
    private mutating func generateAddressesIfNeeded(for usage: DerivationPath.Usage) async throws {
        let entries = getEntries(of: usage)
        let usedAddresses = getUsedAddresses(of: usage)
        
        let numberOfUsedAddresses = usedAddresses.count
        let numberOfRemainingUnusedAddresses = (entries.count - numberOfUsedAddresses)
        
        if numberOfRemainingUnusedAddresses <= gapLimit {
            try await generateAddresses(for: usage, numberOfNewEntries: gapLimit)
        }
    }

    private mutating func generateAddresses(for usage: DerivationPath.Usage, isUsed: Bool = false, numberOfNewEntries: Int) async throws {
        let entries = getEntries(of: usage)
        
        for index in (entries.count) ..< (entries.count + numberOfNewEntries) {
            try await generateAddress(for: usage, at: UInt32(index), isUsed: isUsed)
        }
    }
    
    private mutating func generateAddress(for usage: DerivationPath.Usage, at index: UInt32, isUsed: Bool = false) async throws {
        let (address, privateKey) = try generateAddress(for: usage, at: index)
        addressToPrivateKey[address] = privateKey
        
        let balance = try await address.fetchBalance(using: fulcrum)
        let cache = Entry.Cache(balance: balance, lastUpdated: Date())
        let newEntry = Entry(usage: usage, address: address, isUsed: isUsed, cache: cache)
        
        switch usage {
        case .receiving:
            if receiving.count <= index { receiving.append(newEntry) }
            else { receiving[Int(index)] = newEntry }
        case .change:
            if change.count <= index { change.append(newEntry) }
            else { change[Int(index)] = newEntry }
        }
    }
    
    private mutating func generateAddress(for usage: DerivationPath.Usage, at index: UInt32) throws -> (Address, PrivateKey) {
        let childKey = try extendedKey
            .deriveChildPrivateKey(at: usage.index)
            .deriveChildPrivateKey(at: index)
        
        let privateKey = try PrivateKey(data: childKey.privateKey)
        let publicKey = try PublicKey(privateKey: privateKey)
        let publicKeyHash = PublicKey.Hash(publicKey: publicKey)
        let address = try Address(script: .p2pkh(hash: publicKeyHash))
        
        return (address, privateKey)
    }
}

// MARK: - Address: Getting
extension Address.Book {
    private func getUsedAddresses(of usage: DerivationPath.Usage) -> Set<Address> {
        let usedEntries = getEntries(of: usage).filter { $0.isUsed }
        let usedAddresses = usedEntries.map { $0.address }
        return Set<Address>(usedAddresses)
    }
    
    mutating func getNextAddress(for usage: DerivationPath.Usage) async throws -> Address {
        let entries = getEntries(of: usage)
        let usedAddresses = getUsedAddresses(of: usage)
        
        guard entries.count < maxIndex else { throw Error.indexOutOfBounds }
        
        if entries.isEmpty || usedAddresses.count == entries.count {
            try await generateAddresses(for: usage, numberOfNewEntries: gapLimit)
        }
        
        guard let nextEntry = entries.first(where: { !$0.isUsed }) else { throw Error.addressNotFound }
        return nextEntry.address
    }
}

// MARK: - Key
extension Address.Book {
    func getPrivateKey(for address: Address) throws -> PrivateKey {
        guard let privateKey = addressToPrivateKey[address] else { throw Error.privateKeyNotFound }
        return privateKey
    }
    
    func getPrivateKeys(for utxos: [Transaction.Output.Unspent]) throws -> [Transaction.Output.Unspent: PrivateKey] {
        var pair: [Transaction.Output.Unspent: PrivateKey] = [:]
        
        for utxo in utxos {
            let lockingScript = utxo.lockingScript
            let script = try Script.decode(lockingScript: lockingScript)
            let address = try Address(script: script)
            let privateKey = try getPrivateKey(for: address)
            pair[utxo] = privateKey
        }
        
        return pair
    }
}

// MARK: - Used
extension Address.Book {
    mutating func markAddressAsUsed(_ address: Address) async throws {
        let numberOfAddressesInReceiving = receiving.filter{$0.address == address}.count
        let numberOfAddressesInChange = change.filter{$0.address == address}.count
        
        var usage: DerivationPath.Usage?
        
        if (numberOfAddressesInReceiving + numberOfAddressesInChange) == 0 { throw Error.addressNotFound }
        else if (numberOfAddressesInReceiving == 1 && numberOfAddressesInChange == 0) { usage = .receiving }
        else if (numberOfAddressesInReceiving == 0 && numberOfAddressesInChange == 1) { usage = .change }
        else { throw Error.addressDuplicated }
        
        guard let usage = usage else { throw Error.addressNotFound }
        
        switch usage {
        case .receiving:
            guard let index = receiving.firstIndex(where: {$0.address == address}) else { throw Error.addressNotFound }
            receiving[index].isUsed = true
        case .change:
            guard let index = change.firstIndex(where: {$0.address == address}) else { throw Error.addressNotFound }
            receiving[index].isUsed = true
        }
        
        try await generateAddressesIfNeeded(for: usage)
    }
    
    func isAddressUsed(_ address: Address) -> Bool {
        return receiving.contains(where: {$0.address == address}) || change.contains(where: {$0.address == address})
    }
    
    mutating func updateLatestUsedStatus() async throws {
        try await updateUsedStatus(for: .receiving)
        try await updateUsedStatus(for: .change)
    }

    private mutating func updateUsedStatus(for usage: DerivationPath.Usage) async throws {
        let entries = getEntries(of: usage)
        
        for (index, entry) in entries.enumerated() {
            let transactionHistory = try await entry.address.fetchTransactionHistory(fulcrum: fulcrum)
            
            if !transactionHistory.isEmpty {
                switch usage {
                case .receiving:
                    receiving[index].isUsed = true
                case .change:
                    change[index].isUsed = true
                }
            }
        }
    }
}

// MARK: - Transaction
extension Address.Book {
    mutating func handleIncomingTransaction(_ detailedTransaction: Transaction.Detailed) throws {
        for (index, output) in detailedTransaction.transaction.outputs.enumerated() {
            let lockingScript = output.lockingScript
            let address = try Address(script: .decode(lockingScript: lockingScript))
            
            if addressToPrivateKey.keys.contains(address) {
                let utxo = Transaction.Output.Unspent(output: output,
                                                      previousTransactionHash: .init(naturalOrder: detailedTransaction.hash),
                                                      previousTransactionOutputIndex: UInt32(index))
                addUTXO(utxo)
            }
        }
    }
    
    mutating func handleOutgoingTransaction(_ transaction: Transaction) {
        for input in transaction.inputs {
            if let utxo = utxos.first(
                where: {
                    $0.previousTransactionHash == input.previousTransactionHash && $0.previousTransactionOutputIndex == input.previousTransactionOutputIndex
                }
            ) {
                removeUTXO(utxo)
            }
        }
    }
}

// MARK: - Balance
extension Address.Book {
    func getBalanceFromCache() throws -> Satoshi {
        return try Satoshi((receiving + change).map { $0.cache.balance.uint64 }.reduce(0, +))
    }
    
    mutating func getBalance(willUpdateCache: Bool = true) async throws -> Satoshi {
        if willUpdateCache { try await updateCache(in: (receiving + change)) }
        return try getBalanceFromCache()
    }
    
    mutating func getBalance(for address: Address, willUpdateCache: Bool = true) async throws -> Satoshi {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        if willUpdateCache, !entry.cache.isValid {
            let newBalance = try await address.fetchBalance(using: fulcrum)
            try updateCache(for: address, with: newBalance)
            return newBalance
        } else {
            return entry.cache.balance
        }
    }
}

// MARK: - Cache
extension Address.Book {
    mutating func updateCache(in entries: [Entry]) async throws {
        for entry in entries where !entry.cache.isValid {
            let address = entry.address
            let latestBalance = try await address.fetchBalance(using: fulcrum)
            try updateCache(for: address, with: latestBalance)
        }
    }
    
    mutating func updateCache(for address: Address, with balance: Satoshi) throws {
        guard let existingEntry = findEntry(for: address) else { throw Error.entryNotFound }
        
        let newCache = Entry.Cache(balance: balance,
                                   lastUpdated: Date())
        
        let newEntry = Entry(usage: existingEntry.usage,
                             address: address,
                             isUsed: existingEntry.isUsed,
                             cache: newCache)
        
        switch existingEntry.usage {
        case .receiving:
            guard let index = receiving.firstIndex(where: { $0.address == address }) else { throw Error.entryNotFound }
            receiving[index] = newEntry
        case .change:
            guard let index = change.firstIndex(where: { $0.address == address }) else { throw Error.entryNotFound }
            change[index] = newEntry
        }
    }
}
