import Foundation

struct DerivationPath {
    let purpose: Purpose
    let coinType: CoinType
    var account: Account
    let usage: Usage
    let index: UInt32
    
    init(purpose: Purpose = .bip44, coinType: CoinType = .bitcoinCash, account: Account = .init(index: 0), usage: Usage, index: UInt32) {
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        self.usage = usage
        self.index = index
    }
    
    var path: String {
        return "m/\(purpose.index & ~0x80000000)'/\(coinType.index & ~0x80000000)'/\(account.index & ~0x80000000)'/\(usage.index)/\(index)"
    }
}

extension DerivationPath: Hashable {
    static func == (lhs: DerivationPath, rhs: DerivationPath) -> Bool {
        lhs.path == rhs.path
    }
}

extension DerivationPath.Account: Hashable {
    static func == (lhs: DerivationPath.Account, rhs: DerivationPath.Account) -> Bool {
        lhs.index == rhs.index
    }
}

extension DerivationPath: CustomDebugStringConvertible {
    var debugDescription: String {
        return path
    }
}

extension DerivationPath {
    enum Purpose {
        case bip44
        
        var index: UInt32 {
            switch self {
            case .bip44:
                44 | 0x80000000
            }
        }
    }

    enum CoinType {
        case bitcoin
        case bitcoinCash
        
        var index: UInt32 {
            switch self {
            case .bitcoin:
                0 | 0x80000000
            case .bitcoinCash:
                145 | 0x80000000
            }
        }
    }

    struct Account {
        private(set) var index: UInt32
        
        init(index: UInt32) {
            self.index = index | 0x80000000
        }
        
        mutating func increase() {
            let currentIndex = index & ~0x80000000
            self.index = (currentIndex + 1) | 0x80000000
        }
    }

    enum Usage: CaseIterable {
        case receiving
        case change
        
        var index: UInt32 {
            switch self {
            case .receiving:
                0
            case .change:
                1
            }
        }
    }
}
