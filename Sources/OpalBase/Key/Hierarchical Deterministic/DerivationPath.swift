import Foundation

struct DerivationPath {
    let purpose: Purpose
    let coinType: CoinType
    var account: Account
    let usage: Usage
    let index: UInt32
    
    init(purpose: Purpose = .bip44,
         coinType: CoinType = .bitcoinCash,
         account: Account,
         usage: Usage,
         index: UInt32) throws {
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        self.usage = usage
        self.index = index
    }
    
    var path: String {
        do {
            return try "m/\(purpose.hardenedIndex.unharden())'/\(coinType.hardenedIndex.unharden())'/\(account.unhardenedIndex.harden())'/\(usage.unhardenedIndex)/\(index)"
        } catch {
            print("The error \(error) occured during unhardening one of the indice of \(purpose.hardenedIndex), \(coinType.hardenedIndex), or \(account.unhardenedIndex).")
            return "‼ PATH without hardening: m/\(purpose.hardenedIndex)/\(coinType.hardenedIndex)/\(account.unhardenedIndex)/\(usage.unhardenedIndex)/\(index)"
        }
    }
}

extension DerivationPath: Hashable {
    static func == (lhs: DerivationPath, rhs: DerivationPath) -> Bool {
        lhs.path == rhs.path
    }
}

extension DerivationPath.Account: Hashable {
    static func == (lhs: DerivationPath.Account, rhs: DerivationPath.Account) -> Bool {
        lhs.unhardenedIndex == rhs.unhardenedIndex
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
        
        var hardenedIndex: UInt32 {
            switch self {
            case .bip44:
                do { return try UInt32(44).harden() }
                catch { fatalError("The index number 44 failed to be hardened.") }
            }
        }
    }

    enum CoinType {
        case bitcoin
        case bitcoinCash
        
        var hardenedIndex: UInt32 {
            switch self {
            case .bitcoin:
                do { return try UInt32(0).harden() }
                catch { fatalError("The index number 0 failed to be hardened.") }
            case .bitcoinCash:
                do { return try UInt32(145).harden() }
                catch { fatalError("The index number 145 failed to be hardened.") }
            }
        }
    }

    struct Account {
        private(set) var unhardenedIndex: UInt32
        
        init(unhardenedIndex: UInt32) {
            self.unhardenedIndex = unhardenedIndex
        }
        
        func getHardenedIndex() throws -> UInt32 {
            return try self.unhardenedIndex.harden()
        }
        
        mutating func increase() throws {
            let currentIndex = unhardenedIndex
            guard currentIndex < 0x7FFFFFFF else { throw Error.indexOverflow }
            self.unhardenedIndex = try (currentIndex + 1).harden()
        }
    }

    enum Usage: CaseIterable {
        case receiving
        case change
        
        var unhardenedIndex: UInt32 {
            switch self {
            case .receiving:
                0
            case .change:
                1
            }
        }
    }
}
