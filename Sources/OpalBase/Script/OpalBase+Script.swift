// OpalBase+Script.swift

import Foundation

extension OpalBase {
    public enum Script {
        case p2pk(publicKey: OpalBase.Key.PublicKey)
        case p2pkh_OPCHECKSIG(hash: OpalBase.Key.PublicKey.Hash)
        case p2pkh_OPCHECKDATASIG(hash: OpalBase.Key.PublicKey.Hash)
        case p2ms(numberOfRequiredSignatures: Int, publicKeys: [OpalBase.Key.PublicKey])
        case p2sh(scriptHash: Data)
        
        var data: Data {
            switch self {
            case .p2pk(let publicKey):
                var data = Data()
                data.append(ScriptOperationCode._PUSHBYTES_33.data)
                data.append(publicKey.compressedData)
                data.append(ScriptOperationCode._CHECKSIG.data)
                return data
                
            case .p2pkh_OPCHECKSIG(let hash):
                var data = Data()
                data.append(ScriptOperationCode._DUP.data)
                data.append(ScriptOperationCode._HASH160.data)
                data.append(ScriptOperationCode._PUSHBYTES_20.data)
                data.append(hash.data)
                data.append(ScriptOperationCode._EQUALVERIFY.data)
                data.append(ScriptOperationCode._CHECKSIG.data)
                return data
                
            case .p2pkh_OPCHECKDATASIG(let hash):
                var data = Data()
                data.append(ScriptOperationCode._DUP.data)
                data.append(ScriptOperationCode._HASH160.data)
                data.append(ScriptOperationCode._PUSHBYTES_20.data)
                data.append(hash.data)
                data.append(ScriptOperationCode._EQUALVERIFY.data)
                data.append(ScriptOperationCode._CHECKDATASIG.data)
                return data
                
            case .p2ms(let numberOfRequiredSignatures, let publicKeys):
                var data = Data()
                data.append(ScriptOperationCode(rawValue: UInt8(Int(ScriptOperationCode._1.rawValue) + numberOfRequiredSignatures - 1))!.data)
                for publicKey in publicKeys {
                    data.append(ScriptOperationCode._PUSHBYTES_33.data)
                    data.append(publicKey.compressedData)
                }
                data.append(ScriptOperationCode(rawValue: UInt8(Int(ScriptOperationCode._1.rawValue) + publicKeys.count - 1))!.data)
                data.append(ScriptOperationCode._CHECKMULTISIG.data)
                return data
                
            case .p2sh(let scriptHash):
                var data = Data()
                data.append(ScriptOperationCode._HASH160.data)
                data.append(ScriptOperationCode._PUSHBYTES_20.data)
                data.append(scriptHash)
                data.append(ScriptOperationCode._EQUAL.data)
                return data
            }
        }
    }
}

extension _OpalBase.Script {
    public static func decode(lockingScript: Data) throws -> OpalBase.Script {
        var index = 0
        
        func readByte() -> UInt8? {
            guard index < lockingScript.count else { return nil }
            defer { index += 1 }
            return lockingScript[index]
        }
        
        func readData(length: Int) -> Data? {
            guard index + length <= lockingScript.count else { return nil }
            defer { index += length }
            return lockingScript.subdata(in: index..<index + length)
        }

        func requireEndOfScript() throws {
            guard index == lockingScript.count else {
                throw Error.cannotDecodeScript
            }
        }
        
        while index < lockingScript.count {
            guard let opcode = readByte() else { break }
            
            switch opcode {
            case ScriptOperationCode._DUP.rawValue:
                guard readByte() == ScriptOperationCode._HASH160.rawValue,
                      readByte() == ScriptOperationCode._PUSHBYTES_20.rawValue,
                      let hash = readData(length: 20),
                      readByte() == ScriptOperationCode._EQUALVERIFY.rawValue,
                      let finalOp = readByte()
                else { throw Error.invalidP2PKHScript }
                
                let publicKeyHash = OpalBase.Key.PublicKey.Hash(hash)
                switch finalOp {
                case ScriptOperationCode._CHECKSIG.rawValue:
                    try requireEndOfScript()
                    return .p2pkh_OPCHECKSIG(hash: publicKeyHash)
                case ScriptOperationCode._CHECKDATASIG.rawValue:
                    try requireEndOfScript()
                    return .p2pkh_OPCHECKDATASIG(hash: publicKeyHash)
                default:
                    throw Error.invalidP2PKHScript
                }
            case ScriptOperationCode._PUSHBYTES_33.rawValue:
                guard let publicKeyData = readData(length: 33),
                      readByte() == ScriptOperationCode._CHECKSIG.rawValue
                else { throw Error.invalidP2PKScript }
                
                let publicKey = try OpalBase.Key.PublicKey(compressedData: publicKeyData)
                try requireEndOfScript()
                return .p2pk(publicKey: publicKey)
            case ScriptOperationCode._HASH160.rawValue:
                guard readByte() == ScriptOperationCode._PUSHBYTES_20.rawValue,
                      let scriptHash = readData(length: 20),
                      readByte() == ScriptOperationCode._EQUAL.rawValue
                else { throw Error.invalidP2SHScript }
                
                try requireEndOfScript()
                return .p2sh(scriptHash: scriptHash)
                
            case ScriptOperationCode._1.rawValue...ScriptOperationCode._16.rawValue:
                let numberOfRequiredSignatures = Int(opcode - ScriptOperationCode._1.rawValue) + 1
                var publicKeys: [OpalBase.Key.PublicKey] = .init()
                
                while index < lockingScript.count {
                    let nextOpcode = lockingScript[index]
                    if (ScriptOperationCode._1.rawValue...ScriptOperationCode._16.rawValue).contains(nextOpcode) {
                        break
                    }
                    
                    guard nextOpcode == ScriptOperationCode._PUSHBYTES_33.rawValue,
                          readByte() == ScriptOperationCode._PUSHBYTES_33.rawValue,
                          let publicKeyData = readData(length: 33)
                    else { throw Error.invalidP2MSScript }
                    
                    let publicKey = try OpalBase.Key.PublicKey(compressedData: publicKeyData)
                    publicKeys.append(publicKey)
                }
                
                guard !publicKeys.isEmpty,
                      let publicKeyCountOpcode = readByte(),
                      publicKeyCountOpcode >= ScriptOperationCode._1.rawValue,
                      publicKeyCountOpcode <= ScriptOperationCode._16.rawValue
                else { throw Error.invalidP2MSScript }
                
                let reportedPublicKeyCount = Int(publicKeyCountOpcode - ScriptOperationCode._1.rawValue) + 1
                
                guard reportedPublicKeyCount == publicKeys.count,
                      reportedPublicKeyCount >= numberOfRequiredSignatures,
                      let finalOpcode = readByte(),
                      finalOpcode == ScriptOperationCode._CHECKMULTISIG.rawValue
                else { throw Error.invalidP2MSScript }
                
                try requireEndOfScript()
                return .p2ms(numberOfRequiredSignatures: numberOfRequiredSignatures, publicKeys: publicKeys)
                
            default:
                throw Error.cannotDecodeScript
            }
        }
        
        throw Error.cannotDecodeScript
    }
}

extension _OpalBase.Script {
    var isDerivableFromAddress: Bool {
        switch self {
        case .p2pkh_OPCHECKSIG, .p2pkh_OPCHECKDATASIG, .p2sh: true
        case .p2pk, .p2ms: false
        }
    }
}

extension _OpalBase.Script: Hashable {
    public static func == (lhs: OpalBase.Script, rhs: OpalBase.Script) -> Bool {
        lhs.data == rhs.data
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(data)
    }
}

extension _OpalBase.Script: Sendable {}
