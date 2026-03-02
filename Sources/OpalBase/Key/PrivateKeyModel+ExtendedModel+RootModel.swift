// PrivateKeyModel+ExtendedModel+RootModel.swift

import Foundation
import OpalCrypto

extension PrivateKeyModel.ExtendedModel {
    struct RootModel {
        let privateKey: Data
        let chainCode: Data
        
        init(seed: Data, stringKey: String = "Bitcoin seed") throws {
            guard let key = stringKey.data(using: .utf8) else { throw PrivateKeyModel.Error.invalidStringKey }
            let hmac = HashBasedMessageAuthenticationCodeSecureHashAlgorithm512Model.hash(seed, key: key)
            let privateKeyData = Data(hmac.prefix(32))
            let chainCodeData = Data(hmac.suffix(32))
            
            self.privateKey = privateKeyData
            self.chainCode = chainCodeData
        }
    }
}
