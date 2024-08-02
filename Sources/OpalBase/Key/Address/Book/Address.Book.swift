import Foundation

extension Address {
    struct Book {
        private var extendedKey: PrivateKey.Extended
        private var addressToPrivateKey = [Address: PrivateKey]()
        
        private var receiving = [Entry]()
        private var change = [Entry]()
        
        private let gapLimit = 20
        private let maxIndex = UInt32.max
        
        init(extendedKey: PrivateKey.Extended) throws {
            self.extendedKey = extendedKey
            try generateInitialAddresses()
        }
        
        struct Entry {
            let usage: DerivationPath.Usage
            let address: Address
            var isUsed: Bool
        }
    }
}

extension Address.Book {
    private func getEntries(of usage: DerivationPath.Usage) -> [Entry] {
        switch usage {
        case .receiving:
            return receiving
        case .change:
            return change
        }
    }
}

extension Address.Book {
    private mutating func generateInitialAddresses() throws {
        try generateAddresses(for: .receiving, numberOfNewEntries: gapLimit)
        try generateAddresses(for: .change, numberOfNewEntries: gapLimit)
    }
    
    private mutating func generateAddressesIfNeeded(for usage: DerivationPath.Usage) throws {
        let entries = getEntries(of: usage)
        let usedAddresses = getUsedAddresses(of: usage)
        
        let numberOfUsedAddresses = usedAddresses.count
        let numberOfRemainingUnusedAddresses = (entries.count - numberOfUsedAddresses)
        
        if numberOfRemainingUnusedAddresses <= gapLimit {
            try generateAddresses(for: usage, numberOfNewEntries: gapLimit)
        }
    }
    
    private mutating func generateAddress(for usage: DerivationPath.Usage, at index: UInt32, isUsed: Bool = false) throws {
        let (address, privateKey) = try generateAddress(at: index, usage: usage)
        addressToPrivateKey[address] = privateKey
        
        let newEntry = Entry(usage: usage, address: address, isUsed: isUsed)
        
        switch usage {
        case .receiving:
            if receiving.count <= index { receiving.append(newEntry) }
            else { receiving[Int(index)] = newEntry }
        case .change:
            if change.count <= index { change.append(newEntry) }
            else { change[Int(index)] = newEntry }
        }
    }
    
    private mutating func generateAddresses(for usage: DerivationPath.Usage, isUsed: Bool = false, numberOfNewEntries: Int) throws {
        let entries = getEntries(of: usage)
        
        for index in (entries.count) ..< (entries.count + numberOfNewEntries) {
            try generateAddress(for: usage, at: UInt32(index), isUsed: isUsed)
        }
    }
    
    private mutating func generateAddress(at index: UInt32, usage: DerivationPath.Usage) throws -> (Address, PrivateKey) {
        let childKey = try extendedKey
            .deriveChildPrivateKey(at: usage.index)
            .deriveChildPrivateKey(at: index)
        
        let privateKey = try PrivateKey(data: childKey.privateKey)
        let publicKey = try PublicKey(privateKey: privateKey)
        let publicKeyHash = PublicKey.Hash(publicKey: publicKey)
        let address = try Address(.p2pkh(hash: publicKeyHash))
        
        return (address, privateKey)
    }
}

extension Address.Book {
    func getPrivateKey(for address: Address) throws -> PrivateKey {
        guard let privateKey = addressToPrivateKey[address] else { throw Error.privateKeyNotFound }
        return privateKey
    }
    
    private func getUsedAddresses(of usage: DerivationPath.Usage) -> Set<Address> {
        let usedEntries = getEntries(of: usage).filter { $0.isUsed }
        let usedAddresses = usedEntries.map { $0.address }
        return Set<Address>(usedAddresses)
    }
    
    mutating func getNextAddress(for usage: DerivationPath.Usage) throws -> Address {
        let entries = getEntries(of: usage)
        let usedAddresses = getUsedAddresses(of: usage)
        
        guard entries.count < maxIndex else { throw Error.indexOutOfBounds }
        
        if entries.isEmpty || usedAddresses.count == entries.count {
            try generateAddresses(for: usage, numberOfNewEntries: gapLimit)
        }
        
        guard let nextEntry = entries.first(where: { !$0.isUsed }) else { throw Error.addressIsNotFoundInAddressBook }
        return nextEntry.address
    }
}

extension Address.Book {
    mutating func markAddressAsUsed(_ address: Address) throws {
        let numberOfAddressesInReceiving = receiving.filter{$0.address == address}.count
        let numberOfAddressesInChange = change.filter{$0.address == address}.count
        
        var usage: DerivationPath.Usage?
        
        if (numberOfAddressesInReceiving + numberOfAddressesInChange) == 0 { throw Error.addressIsNotFoundInAddressBook }
        else if (numberOfAddressesInReceiving == 1 && numberOfAddressesInChange == 0) { usage = .receiving }
        else if (numberOfAddressesInReceiving == 0 && numberOfAddressesInChange == 1) { usage = .change }
        else { throw Error.addressIsDuplicated }
        
        guard let usage = usage else { throw Error.addressIsNotFoundInAddressBook }
        
        switch usage {
        case .receiving:
            guard let index = receiving.firstIndex(where: {$0.address == address}) else { throw Error.addressIsNotFoundInAddressBook }
            receiving[index].isUsed = true
        case .change:
            guard let index = change.firstIndex(where: {$0.address == address}) else { throw Error.addressIsNotFoundInAddressBook }
            receiving[index].isUsed = true
        }
        
        try generateAddressesIfNeeded(for: usage)
    }
    
    func isAddressUsed(_ address: Address) -> Bool {
        return receiving.contains(where: {$0.address == address}) || change.contains(where: {$0.address == address})
    }
}

extension Address.Book {
    mutating func updateLatestStatus() async throws {
        try await updateStatus(for: .receiving)
        try await updateStatus(for: .change)
    }
    
    private mutating func updateStatus(for usage: DerivationPath.Usage) async throws {
        let entries = getEntries(of: usage)
        
        for (index, entry) in entries.enumerated() {
            let transactionHistory = try await entry.address.fetchTransactionHistory(awaitSeconds: 1)
            
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
