// OpalBase+PrivateKey.swift

import Foundation

extension OpalBase {
    public struct PrivateKey {
        let rawData: Data
        
        public init() throws {
            var randomBytes: [UInt8] = .init()
            var isValidPrivateKey = false
            
            repeat {
                do {
                    randomBytes = try SecureRandomModel.makeBytes(count: 32)
                } catch {
                    throw Error.randomBytesGenerationFailed
                }
                
                isValidPrivateKey = Secp256k1Model.Operation.validatePrivateKey32(Data(randomBytes))
            } while !isValidPrivateKey
            
            self.rawData = Data(randomBytes)
        }
        
        public init(data: Data) throws {
            guard Secp256k1Model.Operation.validatePrivateKey32(data) else { throw Error.outOfBounds }
            self.rawData = data
        }
    }
}

extension _OpalBase.PrivateKey: Sendable {}
extension _OpalBase.PrivateKey: Hashable {}
extension _OpalBase.PrivateKey: Equatable {}
