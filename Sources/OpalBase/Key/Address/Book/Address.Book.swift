import Foundation
import SwiftFulcrum

extension Address {
    public actor Book {
        private let rootExtendedKey: PrivateKey.Extended
        private let purpose: DerivationPath.Purpose
        private let coinType: DerivationPath.CoinType
        private let account: DerivationPath.Account
        
        private var derivationPathToAddress: [DerivationPath: Address] = .init()
        
        var receivingEntries: [Entry] = .init()
        var changeEntries: [Entry] = .init()
        
        var addressToEntry: [Address: Entry] = .init()
        
        var utxos: Set<Transaction.Output.Unspent> = .init()
        
        let gapLimit: Int
        let maxIndex = UInt32.max
        
        init(rootExtendedKey: PrivateKey.Extended,
             purpose: DerivationPath.Purpose,
             coinType: DerivationPath.CoinType,
             account: DerivationPath.Account,
             gapLimit: Int = 20) async throws {
            self.rootExtendedKey = rootExtendedKey
            self.purpose = purpose
            self.coinType = coinType
            self.account = account
            
            self.gapLimit = gapLimit
            
            try initializeEntries()
            
            for entry in receivingEntries + changeEntries {
                addressToEntry[entry.address] = entry
            }
        }
    }
}

extension Address.Book {
    func createDerivationPath(usage: DerivationPath.Usage,
                              index: UInt32) throws -> DerivationPath {
        let derivationPath = try DerivationPath(purpose: self.purpose,
                                                coinType: self.coinType,
                                                account: self.account,
                                                usage: usage,
                                                index: index)
        return derivationPath
    }
    
    func generateAddress(at index: UInt32,
                         for usage: DerivationPath.Usage) throws -> Address {
        let privateKey = try generatePrivateKey(at: index, for: usage)
        let publicKey = try PublicKey(privateKey: privateKey)
        let address = try Address(script: .p2pkh(hash: .init(publicKey: publicKey)))
        
        return address
    }
    
    func generatePrivateKey(at index: UInt32,
                            for usage: DerivationPath.Usage) throws -> PrivateKey {
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        let childKey = try rootExtendedKey.deriveChild(at: derivationPath)
        let privateKey = try PrivateKey(data: childKey.privateKey)
        
        return privateKey
    }
}


// MARK: - Transaction
extension Address.Book {
    func handleIncomingTransaction(_ detailedTransaction: Transaction.Detailed) throws {
        for (index, output) in detailedTransaction.transaction.outputs.enumerated() {
            let lockingScript = output.lockingScript
            let address = try Address(script: .decode(lockingScript: lockingScript))
            
            if derivationPathToAddress.values.contains(address) {
                let utxo = Transaction.Output.Unspent(output: output,
                                                      previousTransactionHash: .init(naturalOrder: detailedTransaction.hash),
                                                      previousTransactionOutputIndex: UInt32(index))
                addUTXO(utxo)
            }
        }
    }
    
    func handleOutgoingTransaction(_ transaction: Transaction) {
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

/*
extension Address.Book {
    static func generateDummyAddressBook() async -> Address.Book? {
        do {
            let rootExtendedKey = PrivateKey.Extended(rootKey: try .init(seed: .init([0x00])))
            let purpose = DerivationPath.Purpose.bip44
            let coinType = DerivationPath.CoinType.bitcoinCash
            let account = DerivationPath.Account(unhardenedIndex: .max)
            let gapLimit = Int(0)
            return try await .init(rootExtendedKey: rootExtendedKey,
                                   purpose: purpose,
                                   coinType: coinType,
                                   account: account,
                                   gapLimit: gapLimit)
        } catch {
            print("Failable initialization failed: \(error.localizedDescription)")
            return nil
        }
    }
}
*/
