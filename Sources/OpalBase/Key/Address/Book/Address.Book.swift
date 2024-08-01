import Foundation

extension Address {
    struct Book {
        private var extendedKey: PrivateKey.Extended
        private var receivingAddresses = [CashAddress]()
        private var usedReceivingAddresses = Set<CashAddress>()
        private var changeAddresses = [CashAddress]()
        private var usedChangeAddresses = Set<CashAddress>()
        private var addressToPrivateKey = [CashAddress: PrivateKey]()
        private var gapLimit = 20
        
        private let maxIndex = UInt32.max
        
        init(extendedKey: PrivateKey.Extended) throws {
            self.extendedKey = extendedKey
            try generateInitialAddresses()
        }
    }
}

extension Address.Book {
    mutating func updateLatestStatus() async throws {
        try await updateStatus(for: .receiving)
        try await updateStatus(for: .change)
    }
    
    private mutating func updateStatus(for usage: DerivationPath.Usage) async throws {
        let addresses = usage == .receiving ? receivingAddresses : changeAddresses
        
        for address in addresses {
            let transactionHistory = try await address.fetchTransactionHistory(awaitSeconds: 1)
            if !transactionHistory.isEmpty {
                switch usage {
                case .receiving:
                    usedReceivingAddresses.insert(address)
                case .change:
                    usedChangeAddresses.insert(address)
                }
            }
        }
    }
}

extension Address.Book {
    func getPrivateKey(for address: CashAddress) throws -> PrivateKey {
        guard let privateKey = addressToPrivateKey[address] else { throw Error.privateKeyNotFound }
        return privateKey
    }
    
    func getUsedReceivingAddresses() -> Set<CashAddress> {
        return usedReceivingAddresses
    }
    
    func getUsedChangeAddresses() -> Set<CashAddress> {
        return usedChangeAddresses
    }
    
    mutating func getNextReceivingAddress() throws -> CashAddress {
        guard receivingAddresses.count < maxIndex else { throw Error.indexOutOfBounds }
        if receivingAddresses.isEmpty || usedReceivingAddresses.count == receivingAddresses.count {
            try generateReceivingAddresses(gapLimit)
        }
        if let nextAddress = receivingAddresses.first(where: { !usedReceivingAddresses.contains($0) }) {
            return nextAddress
        } else {
            let (address, privateKey) = try generateAddress(at: UInt32(receivingAddresses.count), usage: .receiving)
            receivingAddresses.append(address)
            addressToPrivateKey[address] = privateKey
            return address
        }
    }
    
    mutating func getNextChangeAddress() throws -> CashAddress {
        guard changeAddresses.count < maxIndex else { throw Error.indexOutOfBounds }
        if changeAddresses.isEmpty || usedChangeAddresses.count == usedChangeAddresses.count {
            try generateChangeAddresses(gapLimit)
        }
        if let nextAddress = changeAddresses.first(where: { !usedChangeAddresses.contains($0) }) {
            return nextAddress
        } else {
            let (address, privateKey) = try generateAddress(at: UInt32(changeAddresses.count), usage: .change)
            changeAddresses.append(address)
            addressToPrivateKey[address] = privateKey
            return address
        }
    }
}

extension Address.Book {
    mutating func markAddressAsUsed(_ address: CashAddress) throws {
        if receivingAddresses.contains(address) {
            usedReceivingAddresses.insert(address)
            try generateAddressesIfNeeded(for: .receiving)
        } else if changeAddresses.contains(address) {
            usedChangeAddresses.insert(address)
            try generateAddressesIfNeeded(for: .change)
        } else {
            throw Error.addressIsNotFoundInAddressBook
        }
        
    }
    
    func isAddressUsed(_ address: CashAddress, usage: DerivationPath.Usage) -> Bool {
        switch usage {
        case .receiving:
            return usedReceivingAddresses.contains(address)
        case .change:
            return usedChangeAddresses.contains(address)
        }
    }
}

extension Address.Book {
    private mutating func generateInitialAddresses() throws {
        try generateReceivingAddresses(gapLimit)
        try generateChangeAddresses(gapLimit)
    }
    
    private mutating func generateReceivingAddresses(_ count: Int) throws {
        for index in receivingAddresses.count..<(receivingAddresses.count + count) {
            let (address, privateKey) = try generateAddress(at: UInt32(index), usage: .receiving)
            receivingAddresses.append(address)
            addressToPrivateKey[address] = privateKey
        }
    }
    
    private mutating func generateChangeAddresses(_ count: Int) throws {
        for index in changeAddresses.count..<(changeAddresses.count + count) {
            let (address, privateKey) = try generateAddress(at: UInt32(index), usage: .change)
            changeAddresses.append(address)
            addressToPrivateKey[address] = privateKey
        }
    }
    
    private mutating func generateAddressesIfNeeded(for usage: DerivationPath.Usage) throws {
        switch usage {
        case .receiving:
            if receivingAddresses.count - usedReceivingAddresses.count <= gapLimit {
                try generateReceivingAddresses(gapLimit)
            }
        case .change:
            if changeAddresses.count - usedChangeAddresses.count <= gapLimit {
                try generateChangeAddresses(gapLimit)
            }
        }
    }
    
    private mutating func generateAddress(at index: UInt32, usage: DerivationPath.Usage) throws -> (CashAddress, PrivateKey) {
        let childKey = try extendedKey
            .deriveChildPrivateKey(at: usage.index)
            .deriveChildPrivateKey(at: index)
        
        let privateKey = try PrivateKey(data: childKey.privateKey)
        let publicKey = try PublicKey(privateKey: privateKey)
        let publicKeyHash = PublicKey.Hash(publicKey: publicKey)
        let address = try CashAddress(.p2pkh(hash: publicKeyHash))
        
        return (address, privateKey)
    }
}
