import Foundation
import SwiftFulcrum

extension Address {
    public struct Book {
        private let rootExtendedKey: PrivateKey.Extended
        private let purpose: DerivationPath.Purpose
        private let coinType: DerivationPath.CoinType
        private let account: DerivationPath.Account
        
        private var derivationPathToAddress = [DerivationPath: Address]()
        
        public var receivingEntries = [Entry]()
        public var changeEntries = [Entry]()
        
        public var utxos = Set<Transaction.Output.Unspent>()
        
        let gapLimit: Int
        let maxIndex = UInt32.max
        
        public init(rootExtendedKey: PrivateKey.Extended,
                    purpose: DerivationPath.Purpose,
                    coinType: DerivationPath.CoinType,
                    account: DerivationPath.Account,
                    gapLimit: Int = 20,
                    fetchBalance: Bool = true,
                    fulcrum: Fulcrum) async throws {
            self.rootExtendedKey = rootExtendedKey
            self.purpose = purpose
            self.coinType = coinType
            self.account = account
            
            self.gapLimit = gapLimit
            
            try await initializeEntries(fetchBalance: fetchBalance, fulcrum: fulcrum)
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
    mutating func handleIncomingTransaction(_ detailedTransaction: Transaction.Detailed) throws {
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

/*
#if DEBUG
extension Address.Book {
    public init(unhardenedAccountIndex: UInt32) {
        self.rootExtendedKey = .init(rootKey: try! .init(seed: (0...100).randomElement()!.data))
        self.purpose = .bip44
        self.coinType = .bitcoinCash
        self.account = .init(unhardenedIndex: unhardenedAccountIndex)
        self.gapLimit = 20
    }
}
#endif
*/
