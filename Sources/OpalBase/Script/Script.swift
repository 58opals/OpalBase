// Script.swift

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
    static func decode(lockingScript: Data) throws -> Script {
        var index = 0
        
        func readByte() -> UInt8? {
            guard index < lockingScript.count else { return nil }
            defer { index += 1 }
            return lockingScript[index]
        }
        
        func readData(length: Int) -> Data? {
            guard index + length <= lockingScript.count else { return nil }
            defer { index += length }
            return lockingScript.subdata(in: index..<index+length)
        }
        
        while index < lockingScript.count {
            guard let opcode = readByte() else { break }
            
            switch opcode {
            case OP._DUP.rawValue:
                guard readByte() == OP._HASH160.rawValue,
                      readByte() == OP._PUSHBYTES_20.rawValue,
                      let hash = readData(length: 20),
                      readByte() == OP._EQUALVERIFY.rawValue,
                      readByte() == OP._CHECKSIG.rawValue else {
                    throw Error.invalidP2PKHScript
                }
                let publicKeyHash = PublicKey.Hash(hash)
                return .p2pkh(hash: publicKeyHash)
                
            case OP._PUSHBYTES_33.rawValue:
                guard let publicKeyData = readData(length: 33),
                      readByte() == OP._CHECKSIG.rawValue else {
                    throw Error.invalidP2PKScript
                }
                let publicKey = try PublicKey(compressedData: publicKeyData)
                return .p2pk(publicKey: publicKey)
                
            case OP._HASH160.rawValue:
                guard readByte() == OP._PUSHBYTES_20.rawValue,
                      let scriptHash = readData(length: 20),
                      readByte() == OP._EQUAL.rawValue else {
                    throw Error.invalidP2SHScript
                }
                return .p2sh(scriptHash: scriptHash)
                
            case OP._1.rawValue...OP._16.rawValue:
                let numberOfRequiredSignatures = Int(opcode - OP._1.rawValue) + 1
                var publicKeys: [PublicKey] = []
                
                while index < lockingScript.count {
                    guard let nextOpcode = readByte(),
                          nextOpcode == OP._PUSHBYTES_33.rawValue,
                          let publicKeyData = readData(length: 33) else {
                        throw Error.invalidP2MSScript
                    }
                    let publicKey = try PublicKey(compressedData: publicKeyData)
                    publicKeys.append(publicKey)
                }
                
                guard let lastOpcode = lockingScript.last,
                      lastOpcode == OP._CHECKMULTISIG.rawValue,
                      publicKeys.count > 0 else {
                    throw Error.invalidP2MSScript
                }
                
                return .p2ms(numberOfRequiredSignatures: numberOfRequiredSignatures, publicKeys: publicKeys)
                
            default:
                break
            }
        }
        
        throw Error.cannotDecodeScript
    }
}


extension Script: Hashable {
    static func == (lhs: Script, rhs: Script) -> Bool {
        lhs.data == rhs.data
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.data)
    }
}

extension Script: Sendable {}
