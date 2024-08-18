import Foundation

extension PrivateKey.Extended {
    public struct Root {
        let privateKey: Data
        let chainCode: Data
        
        public init(seed: Data, stringKey: String = "Bitcoin seed") throws {
            guard let key = stringKey.data(using: .utf8) else { fatalError() }
            let hmac = HMACSHA512.hash(seed, key: key)
            let privateKeyData = Data(hmac.prefix(32))
            let chainCodeData = Data(hmac.suffix(32))
            
            self.privateKey = privateKeyData
            self.chainCode = chainCodeData
        }
    }
}
