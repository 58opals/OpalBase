// OpalBase+Address+Legacy.swift

import Foundation

extension _OpalBase.Address {
    struct Legacy {
        let string: String
        
        init(_ script: OpalBase.Script) throws {
            let prefix: UInt8
            let payload: Data
            switch script {
            case .p2pkh_OPCHECKSIG(let hash):
                guard hash.data.count == 20 else { throw Error.invalidScriptType }
                prefix = 0x00
                payload = hash.data

            case .p2sh(let scriptHash):
                guard scriptHash.count == 20 else { throw Error.invalidScriptType }
                prefix = 0x05
                payload = scriptHash

            default:
                throw Error.invalidScriptType
            }

            let data = Data([prefix]) + payload
            let checksum = Data(OpalCryptoAdapter.hash256(data).prefix(4))
            self.string = OpalCryptoAdapter.encodeBase58(data + checksum)
        }
    }
}

extension _OpalBase.Address.Legacy {
    enum Error: Swift.Error {
        case invalidScriptType
    }
}
