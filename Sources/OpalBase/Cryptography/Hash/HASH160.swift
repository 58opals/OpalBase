import Foundation

struct HASH160 {
    static func hash(data: Data) -> Data {
        let sha256 = SHA256.hash(data: data)
        let ripemd160 = RIPEMD160.hash(data: sha256)
        return ripemd160
    }
}
