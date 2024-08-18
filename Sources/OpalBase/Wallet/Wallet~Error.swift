import Foundation

extension Wallet {
    public enum Error: Swift.Error {
        case cannotGetAccount(index: Int)
    }
}
