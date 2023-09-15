// Opal Base by 58 Opals

import Foundation
import CryptoKit

struct HASH160 {
    private init() {}
    
    static func hash(data: Data) -> Data {
        let sha256 = SHA256.hash(data: data)
        let ripemd160 = RIPEMD160.hash(Data(sha256))
        return ripemd160
    }
}
