// Address+Legacy.swift

import Foundation

extension Address {
    struct Legacy {
        let string: String
        
        init(_ script: Script) throws {
            switch script {
            case .p2pkh(let hash):
                let prefix = Data([0x00])
                let hash160 = hash.data
                let data = prefix + hash160
                let checksum = HASH256.getChecksum(data)
                let base58 = Base58.encode(data + checksum)
                self.string = base58
                
            default:
                throw Error.invalidScriptType
            }
        }
    }
}

extension Address.Legacy {
    enum Error: Swift.Error {
        case invalidScriptType
    }
}
