// Script.swift

import Foundation

public enum Script {
    case p2pk(publicKey: PublicKey)
    case p2pkh_OPCHECKSIG(hash: PublicKey.Hash)
    case p2pkh_OPCHECKDATASIG(hash: PublicKey.Hash)
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
            
        case .p2pkh_OPCHECKSIG(let hash):
            var data = Data()
            data.append(OP._DUP.data)
            data.append(OP._HASH160.data)
            data.append(OP._PUSHBYTES_20.data)
            data.append(hash.data)
            data.append(OP._EQUALVERIFY.data)
            data.append(OP._CHECKSIG.data)
            return data
            
        case .p2pkh_OPCHECKDATASIG(let hash):
            var data = Data()
            data.append(OP._DUP.data)
            data.append(OP._HASH160.data)
            data.append(OP._PUSHBYTES_20.data)
            data.append(hash.data)
            data.append(OP._EQUALVERIFY.data)
            data.append(OP._CHECKDATASIG.data)
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
    enum Error: Swift.Error {
        case cannotDecodeScript
        
        case invalidP2PKScript
        case invalidP2PKHScript
        case invalidP2SHScript
        case invalidP2MSScript
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
                      let finalOp = readByte()
                else { throw Error.invalidP2PKHScript }
                
                let publicKeyHash = PublicKey.Hash(hash)
                switch finalOp {
                case OP._CHECKSIG.rawValue:
                    return .p2pkh_OPCHECKSIG(hash: publicKeyHash)
                case OP._CHECKDATASIG.rawValue:
                    return .p2pkh_OPCHECKDATASIG(hash: publicKeyHash)
                default:
                    throw Error.invalidP2PKHScript
                }
            case OP._PUSHBYTES_33.rawValue:
                guard let publicKeyData = readData(length: 33),
                      readByte() == OP._CHECKSIG.rawValue
                else { throw Error.invalidP2PKScript }
                
                let publicKey = try PublicKey(compressedData: publicKeyData)
                return .p2pk(publicKey: publicKey)
            case OP._HASH160.rawValue:
                guard readByte() == OP._PUSHBYTES_20.rawValue,
                      let scriptHash = readData(length: 20),
                      readByte() == OP._EQUAL.rawValue
                else { throw Error.invalidP2SHScript }
                
                return .p2sh(scriptHash: scriptHash)
                
            case OP._1.rawValue...OP._16.rawValue:
                let numberOfRequiredSignatures = Int(opcode - OP._1.rawValue) + 1
                var publicKeys: [PublicKey] = []
                
                while index < lockingScript.count {
                    guard index < lockingScript.count else { throw Error.invalidP2MSScript }
                    
                    let nextOpcode = lockingScript[index]
                    guard nextOpcode == OP._PUSHBYTES_33.rawValue else { break }
                    
                    guard readByte() == OP._PUSHBYTES_33.rawValue,
                          let publicKeyData = readData(length: 33)
                    else { throw Error.invalidP2MSScript }
                    
                    let publicKey = try PublicKey(compressedData: publicKeyData)
                    publicKeys.append(publicKey)
                }
                
                guard !publicKeys.isEmpty,
                      let publicKeyCountOpcode = readByte(),
                      publicKeyCountOpcode >= OP._1.rawValue,
                      publicKeyCountOpcode <= OP._16.rawValue
                else { throw Error.invalidP2MSScript }
                
                let reportedPublicKeyCount = Int(publicKeyCountOpcode - OP._1.rawValue) + 1
                
                guard reportedPublicKeyCount == publicKeys.count,
                      reportedPublicKeyCount >= numberOfRequiredSignatures,
                      let finalOpcode = readByte(),
                      finalOpcode == OP._CHECKMULTISIG.rawValue
                else { throw Error.invalidP2MSScript }
                
                return .p2ms(numberOfRequiredSignatures: numberOfRequiredSignatures,
                             publicKeys: publicKeys)
                
            default:
                break
            }
        }
        
        throw Error.cannotDecodeScript
    }
}

extension Script {
    var isDerivableFromAddress: Bool {
        switch self {
        case .p2pkh_OPCHECKSIG, .p2pkh_OPCHECKDATASIG, .p2sh: true
        case .p2pk, .p2ms: false
        }
    }
}

extension Script: Hashable {
    public static func == (lhs: Script, rhs: Script) -> Bool {
        lhs.data == rhs.data
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.data)
    }
}

extension Script: Sendable {}
