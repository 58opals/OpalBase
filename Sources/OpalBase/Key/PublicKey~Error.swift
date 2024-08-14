import Foundation

extension PublicKey {
    enum Error: Swift.Error {
        case invalidLength
        case publicKeyDerivationFailed
    }
}
