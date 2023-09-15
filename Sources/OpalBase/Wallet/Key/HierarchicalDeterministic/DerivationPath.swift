// Opal Base by 58 Opals

import Foundation

struct DerivationPath: CustomStringConvertible {
    let root: ExtendedPrivateKey
    
    private let purpose: Purpose
    private let coinType: Blockchain.CoinType
    
    init(root: ExtendedPrivateKey, purpose: Purpose = .bip44, coinType: Blockchain.CoinType = .bitcoinCash) {
        self.root = root
        self.purpose = purpose
        self.coinType = coinType
    }
    
    var description: String {
        "[m/\(purpose)/\(coinType.derivationPathIndex)/{account}/{usage}/{index}]"
    }
}

extension DerivationPath {
    func generatePrivateKey(account: Account, usage: Usage, index: Index) -> ExtendedPrivateKey {
        root.diverge(to: purpose.index, depth: purpose.depth)
            .diverge(to: coinType.derivationPathIndex, depth: coinType.derivationPathDepth)
            .diverge(to: account.index, depth: account.depth)
            .diverge(to: usage.index, depth: usage.depth)
            .diverge(to: index, depth: 5)
    }
}

extension DerivationPath {
    enum Purpose: CustomStringConvertible {
        case bip44, bip49, bip84
        
        init(scriptType: Script.Representation) {
            switch scriptType {
            case .p2pkh:
                self = .bip44
            default:
                fatalError()
            }
        }
        
        var representNumber: UInt32 {
            switch self {
            case .bip44: return 44
            case .bip49: return 49
            case .bip84: return 84
            }
        }
        
        var index: Index { .init(representNumber, hardened: true) }
        var depth: UInt8 { 1 }
        var description: String { "\(representNumber.description)h" }
    }
    
    struct Account: CustomStringConvertible {
        let index: Index
        
        init(_ number: UInt32) {
            guard number < DerivationPath.Index.hardenedBranchStartingIndex else { fatalError() }
            self.index = .init(number, hardened: true)
        }
        
        var depth: UInt8 { 3 }
        var description: String { "\(index.representNumber.description)h" }
    }
    
    enum Usage: CustomStringConvertible {
        case receive, change
        
        var representNumber: UInt32 {
            switch self {
            case .receive: return 0
            case .change: return 1
            }
        }
        
        var index: Index { .init(representNumber, hardened: false) }
        var depth: UInt8 { 4 }
        var description: String { "\(representNumber.description)" }
    }
    
    struct Index: CustomStringConvertible {
        static let hardenedBranchStartingIndex: UInt32 = 2_147_483_648
        
        let representNumber: UInt32
        let number: UInt32
        
        init(_ index: UInt32, hardened: Bool = false) {
            guard !(!(index<Index.hardenedBranchStartingIndex) && !hardened) else { fatalError("Index is larger than \(Index.hardenedBranchStartingIndex.description) so this should be hardened.") }
            self.representNumber = index
            self.number = index + (hardened ? Index.hardenedBranchStartingIndex : 0)
        }
        
        var isHardened: Bool { !(number < Index.hardenedBranchStartingIndex) }
        
        var description: String {
            return (number - (isHardened ? Index.hardenedBranchStartingIndex : 0)).description + (isHardened ? "h" : "")
        }
    }
}

extension Blockchain.CoinType {
    var derivationPathNumber: UInt32 {
        switch self {
        case .bitcoin: return 0
        case .bitcoinCash: return 145
        }
    }
    
    var derivationPathIndex: DerivationPath.Index { .init(derivationPathNumber, hardened: true) }
    var derivationPathDepth: UInt8 { 2 }
}
