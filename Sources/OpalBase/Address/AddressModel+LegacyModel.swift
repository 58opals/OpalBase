// AddressModel+LegacyModel.swift

import Foundation

extension AddressModel {
    struct LegacyModel {
        let string: String
        
        init(_ script: ScriptModel) throws {
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

extension AddressModel.LegacyModel {
    enum Error: Swift.Error {
        case invalidScriptType
    }
}
