// OpalBase+CashTokens+BCMR+Client+TokenSnapshot.swift

extension OpalBase.CashTokens.BCMR.Client {
    public struct TokenSnapshot: Codable, Sendable {
        public let category: String?
        public let symbol: String?
        public let decimals: Int?
        
        public init(category: String?, symbol: String?, decimals: Int?) {
            self.category = category
            self.symbol = symbol
            self.decimals = decimals
        }
    }
}
