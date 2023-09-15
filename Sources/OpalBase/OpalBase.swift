// Opal Base by 58 Opals

public struct OpalBase {
    public init() {}
}

extension OpalBase {
    public func generateWallet(with words: [String]? = nil) -> Wallet {
        if let words = words {
            return Wallet(from: words)
        } else {
            return Wallet()
        }
    }
}
