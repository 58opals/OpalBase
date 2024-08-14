import Foundation

extension Address.Book.Entry {
    struct Cache {
        var balance: Satoshi
        var lastUpdated: Date
        let validityDuration: TimeInterval = 60 * 10
        
        var isValid: Bool { Date().timeIntervalSince(lastUpdated) < validityDuration }
    }
}
