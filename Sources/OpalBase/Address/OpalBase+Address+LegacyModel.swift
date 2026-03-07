// OpalBase.Address+LegacyModel.swift

import Foundation

extension _OpalBase.Address {
    struct LegacyModel {
        let string: String
        
        init(_ script: OpalBase.Script) throws {
            switch script {
            case .p2pkh_OPCHECKSIG(let hash), .p2pkh_OPCHECKDATASIG(hash: let hash):
                let prefix = Data([0x00])
                let hash160 = hash.data
                let data = prefix + hash160
                let checksum = HASH256Model.computeChecksum(for: data)
                let base58 = Base58Model.encode(data + checksum)
                self.string = base58
                
            default:
                throw Error.invalidScriptType
            }
        }
    }
}

extension _OpalBase.Address.LegacyModel {
    enum Error: Swift.Error {
        case invalidScriptType
    }
}
