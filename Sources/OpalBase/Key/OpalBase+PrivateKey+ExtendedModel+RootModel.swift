// OpalBase+PrivateKey+ExtendedModel+RootModel.swift

import Foundation

extension _OpalBase.PrivateKey.ExtendedModel {
    struct RootModel {
        let privateKey: Data
        let chainCode: Data
        
        init(seed: Data, stringKey: String = "Bitcoin seed") throws {
            guard let key = stringKey.data(using: .utf8) else { throw OpalBase.PrivateKey.Error.invalidStringKey }
            let hmac = HMACSHA512Model.hash(seed, key: key)
            let privateKeyData = Data(hmac.prefix(32))
            let chainCodeData = Data(hmac.suffix(32))
            
            self.privateKey = privateKeyData
            self.chainCode = chainCodeData
        }
    }
}
