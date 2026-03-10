// OpalBase+Address+Legacy.swift

import Foundation

extension _OpalBase.Address {
    struct Legacy {
        let string: String
        
        init(_ script: OpalBase.Script) throws {
            switch script {
            case .p2pkh_OPCHECKSIG(let hash), .p2pkh_OPCHECKDATASIG(hash: let hash):
                let prefix = Data([0x00])
                let hash160 = hash.data
                let data = prefix + hash160
                let checksum = Data(OpalCryptoAdapter.hash256(data).prefix(4))
                let base58 = OpalCryptoAdapter.encodeBase58(data + checksum)
                self.string = base58
                
            default:
                throw Error.invalidScriptType
            }
        }
    }
}

extension _OpalBase.Address.Legacy {
    enum Error: Swift.Error {
        case invalidScriptType
    }
}
