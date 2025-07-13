// PrivateKey+Extended+Root.swift

import Foundation

extension PrivateKey.Extended {
    struct Root {
        let privateKey: Data
        let chainCode: Data
        
        init(seed: Data, stringKey: String = "Bitcoin seed") throws {
            guard let key = stringKey.data(using: .utf8) else { throw PrivateKey.Error.invalidStringKey }
            let hmac = HMACSHA512.hash(seed, key: key)
            let privateKeyData = Data(hmac.prefix(32))
            let chainCodeData = Data(hmac.suffix(32))
            
            self.privateKey = privateKeyData
            self.chainCode = chainCodeData
        }
    }
}
