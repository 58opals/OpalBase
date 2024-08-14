import Foundation
import CryptoKit

struct HMACSHA512 {
    static func hash(_ data: Data, key: Data) -> Data {
        let input = data
        let key = key
        let hmac = HMAC<SHA512>.authenticationCode(for: input, using: .init(data: key))
        return Data(hmac)
    }
}
