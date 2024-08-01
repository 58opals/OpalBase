import Foundation

enum Script {
    case p2pk(publicKey: PublicKey)
    case p2pkh(hash: PublicKey.Hash)
    case p2ms(numberOfRequiredSignatures: Int, publicKeys: [PublicKey])
    case p2sh(scriptHash: Data)
    
    var data: Data {
        switch self {
        case .p2pk(let publicKey):
            var data = Data()
            data.append(OP._PUSHBYTES_33.data)
            data.append(publicKey.compressedData)
            data.append(OP._CHECKSIG.data)
            return data
            
        case .p2pkh(let hash):
            var data = Data()
            data.append(OP._DUP.data)
            data.append(OP._HASH160.data)
            data.append(OP._PUSHBYTES_20.data)
            data.append(hash.data)
            data.append(OP._EQUALVERIFY.data)
            data.append(OP._CHECKSIG.data)
            return data
            
        case .p2ms(let numberOfRequiredSignatures, let publicKeys):
            var data = Data()
            data.append(OP(rawValue: UInt8(Int(OP._1.rawValue) + numberOfRequiredSignatures - 1))!.data)
            for publicKey in publicKeys {
                data.append(OP._PUSHBYTES_33.data)
                data.append(publicKey.compressedData)
            }
            data.append(OP(rawValue: UInt8(Int(OP._1.rawValue) + publicKeys.count - 1))!.data)
            data.append(OP._CHECKMULTISIG.data)
            return data
            
        case .p2sh(let scriptHash):
            var data = Data()
            data.append(OP._HASH160.data)
            data.append(OP._PUSHBYTES_20.data)
            data.append(scriptHash)
            data.append(OP._EQUAL.data)
            return data
        }
    }
}

extension Script {
    static func decode(scriptPubKey: Data) throws -> Script {
        var index = 0
        
        func readByte() -> UInt8? {
            guard index < scriptPubKey.count else { return nil }
            let byte = scriptPubKey[index]
            index += 1
            return byte
        }
        
        func readData(length: Int) -> Data? {
            guard index + length <= scriptPubKey.count else { return nil }
            let data = scriptPubKey.subdata(in: index..<index+length)
            index += length
            return data
        }
        
        while index < scriptPubKey.count {
            guard let opcode = readByte() else { break }
            
            switch opcode {
            case OP._DUP.rawValue:
                guard let byte2 = readByte(),
                      let byte3 = readByte(),
                      let byte4 = readByte(),
                      let byte5 = readByte(),
                      byte2 == OP._HASH160.rawValue,
                      byte3 == OP._PUSHBYTES_20.rawValue,
                      let hash = readData(length: 20),
                      byte4 == OP._EQUALVERIFY.rawValue,
                      byte5 == OP._CHECKSIG.rawValue else { break }
                let publicKey = try PublicKey(compressedData: hash)
                let publicKeyHash = PublicKey.Hash(publicKey: publicKey)
                return .p2pkh(hash: publicKeyHash)
                
            case OP._PUSHBYTES_33.rawValue:
                guard let publicKeyData = readData(length: 33),
                      let byte2 = readByte(),
                      byte2 == OP._CHECKSIG.rawValue else { break }
                let publicKey = try PublicKey(compressedData: publicKeyData)
                return .p2pk(publicKey: publicKey)
                
            case OP._HASH160.rawValue:
                guard let byte2 = readByte(),
                      byte2 == OP._PUSHBYTES_20.rawValue,
                      let scriptHash = readData(length: 20),
                      let byte3 = readByte(),
                      byte3 == OP._EQUAL.rawValue else { break }
                return .p2sh(scriptHash: scriptHash)
                
            case OP._1.rawValue...OP._16.rawValue:
                let numberOfRequiredSignatures = Int(opcode - OP._1.rawValue) + 1
                var publicKeys: [PublicKey] = []
                while index < scriptPubKey.count {
                    guard let byte = readByte(),
                          byte == OP._PUSHBYTES_33.rawValue,
                          let publicKeyData = readData(length: 33) else { break }
                    let publicKey = try PublicKey(compressedData: publicKeyData)
                    publicKeys.append(publicKey)
                }
                if let lastByte = scriptPubKey.last,
                   lastByte == OP._CHECKMULTISIG.rawValue,
                   publicKeys.count > 0 {
                    return .p2ms(numberOfRequiredSignatures: numberOfRequiredSignatures, publicKeys: publicKeys)
                }
                
            default:
                break
            }
        }
        
        // If no known pattern matches
        throw Error.cannotDecodeScript
    }
}

extension Script {
    enum Error: Swift.Error {
        case cannotDecodeScript
    }
}
