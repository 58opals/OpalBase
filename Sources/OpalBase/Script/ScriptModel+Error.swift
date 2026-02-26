// ScriptModel.swift

import Foundation

public enum ScriptModel {
    case p2pk(publicKey: PublicKeyModel)
    case p2pkh_OPCHECKSIG(hash: PublicKeyModel.HashModel)
    case p2pkh_OPCHECKDATASIG(hash: PublicKeyModel.HashModel)
    case p2ms(numberOfRequiredSignatures: Int, publicKeys: [PublicKeyModel])
    case p2sh(scriptHash: Data)
    
    var data: Data {
        switch self {
        case .p2pk(let publicKey):
            var data = Data()
            data.append(ScriptOperationCodeModel._PUSHBYTES_33.data)
            data.append(publicKey.compressedData)
            data.append(ScriptOperationCodeModel._CHECKSIG.data)
            return data
            
        case .p2pkh_OPCHECKSIG(let hash):
            var data = Data()
            data.append(ScriptOperationCodeModel._DUP.data)
            data.append(ScriptOperationCodeModel._HASH160.data)
            data.append(ScriptOperationCodeModel._PUSHBYTES_20.data)
            data.append(hash.data)
            data.append(ScriptOperationCodeModel._EQUALVERIFY.data)
            data.append(ScriptOperationCodeModel._CHECKSIG.data)
            return data
            
        case .p2pkh_OPCHECKDATASIG(let hash):
            var data = Data()
            data.append(ScriptOperationCodeModel._DUP.data)
            data.append(ScriptOperationCodeModel._HASH160.data)
            data.append(ScriptOperationCodeModel._PUSHBYTES_20.data)
            data.append(hash.data)
            data.append(ScriptOperationCodeModel._EQUALVERIFY.data)
            data.append(ScriptOperationCodeModel._CHECKDATASIG.data)
            return data
            
        case .p2ms(let numberOfRequiredSignatures, let publicKeys):
            var data = Data()
            data.append(ScriptOperationCodeModel(rawValue: UInt8(Int(ScriptOperationCodeModel._1.rawValue) + numberOfRequiredSignatures - 1))!.data)
            for publicKey in publicKeys {
                data.append(ScriptOperationCodeModel._PUSHBYTES_33.data)
                data.append(publicKey.compressedData)
            }
            data.append(ScriptOperationCodeModel(rawValue: UInt8(Int(ScriptOperationCodeModel._1.rawValue) + publicKeys.count - 1))!.data)
            data.append(ScriptOperationCodeModel._CHECKMULTISIG.data)
            return data
            
        case .p2sh(let scriptHash):
            var data = Data()
            data.append(ScriptOperationCodeModel._HASH160.data)
            data.append(ScriptOperationCodeModel._PUSHBYTES_20.data)
            data.append(scriptHash)
            data.append(ScriptOperationCodeModel._EQUAL.data)
            return data
        }
    }
}

extension ScriptModel {
    enum Error: Swift.Error {
        case cannotDecodeScript
        
        case invalidP2PKScript
        case invalidP2PKHScript
        case invalidP2SHScript
        case invalidP2MSScript
    }
}

extension ScriptModel {
    public static func decode(lockingScript: Data) throws -> ScriptModel {
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
            case ScriptOperationCodeModel._DUP.rawValue:
                guard readByte() == ScriptOperationCodeModel._HASH160.rawValue,
                      readByte() == ScriptOperationCodeModel._PUSHBYTES_20.rawValue,
                      let hash = readData(length: 20),
                      readByte() == ScriptOperationCodeModel._EQUALVERIFY.rawValue,
                      let finalOp = readByte()
                else { throw Error.invalidP2PKHScript }
                
                let publicKeyHash = PublicKeyModel.HashModel(hash)
                switch finalOp {
                case ScriptOperationCodeModel._CHECKSIG.rawValue:
                    return .p2pkh_OPCHECKSIG(hash: publicKeyHash)
                case ScriptOperationCodeModel._CHECKDATASIG.rawValue:
                    return .p2pkh_OPCHECKDATASIG(hash: publicKeyHash)
                default:
                    throw Error.invalidP2PKHScript
                }
            case ScriptOperationCodeModel._PUSHBYTES_33.rawValue:
                guard let publicKeyData = readData(length: 33),
                      readByte() == ScriptOperationCodeModel._CHECKSIG.rawValue
                else { throw Error.invalidP2PKScript }
                
                let publicKey = try PublicKeyModel(compressedData: publicKeyData)
                return .p2pk(publicKey: publicKey)
            case ScriptOperationCodeModel._HASH160.rawValue:
                guard readByte() == ScriptOperationCodeModel._PUSHBYTES_20.rawValue,
                      let scriptHash = readData(length: 20),
                      readByte() == ScriptOperationCodeModel._EQUAL.rawValue
                else { throw Error.invalidP2SHScript }
                
                return .p2sh(scriptHash: scriptHash)
                
            case ScriptOperationCodeModel._1.rawValue...ScriptOperationCodeModel._16.rawValue:
                let numberOfRequiredSignatures = Int(opcode - ScriptOperationCodeModel._1.rawValue) + 1
                var publicKeys: [PublicKeyModel] = .init()
                
                while index < lockingScript.count {
                    let nextOpcode = lockingScript[index]
                    if (ScriptOperationCodeModel._1.rawValue...ScriptOperationCodeModel._16.rawValue).contains(nextOpcode) {
                        break
                    }
                    
                    guard nextOpcode == ScriptOperationCodeModel._PUSHBYTES_33.rawValue,
                          readByte() == ScriptOperationCodeModel._PUSHBYTES_33.rawValue,
                          let publicKeyData = readData(length: 33)
                    else { throw Error.invalidP2MSScript }
                    
                    let publicKey = try PublicKeyModel(compressedData: publicKeyData)
                    publicKeys.append(publicKey)
                }
                
                guard !publicKeys.isEmpty,
                      let publicKeyCountOpcode = readByte(),
                      publicKeyCountOpcode >= ScriptOperationCodeModel._1.rawValue,
                      publicKeyCountOpcode <= ScriptOperationCodeModel._16.rawValue
                else { throw Error.invalidP2MSScript }
                
                let reportedPublicKeyCount = Int(publicKeyCountOpcode - ScriptOperationCodeModel._1.rawValue) + 1
                
                guard reportedPublicKeyCount == publicKeys.count,
                      reportedPublicKeyCount >= numberOfRequiredSignatures,
                      let finalOpcode = readByte(),
                      finalOpcode == ScriptOperationCodeModel._CHECKMULTISIG.rawValue
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

extension ScriptModel {
    var isDerivableFromAddress: Bool {
        switch self {
        case .p2pkh_OPCHECKSIG, .p2pkh_OPCHECKDATASIG, .p2sh: true
        case .p2pk, .p2ms: false
        }
    }
}

extension ScriptModel: Hashable {
    public static func == (lhs: ScriptModel, rhs: ScriptModel) -> Bool {
        lhs.data == rhs.data
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.data)
    }
}

extension ScriptModel: Sendable {}
