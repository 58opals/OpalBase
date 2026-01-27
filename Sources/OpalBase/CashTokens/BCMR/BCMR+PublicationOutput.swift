// BCMR+PublicationOutput.swift

import Foundation

extension BitcoinCashMetadataRegistries {
    public struct Publication: Sendable {
        public let sha256: Data
        public let uris: [String]
        
        public init(sha256: Data, uris: [String]) {
            self.sha256 = sha256
            self.uris = uris
        }
    }
    
    static func parsePublicationOutput(lockingScript: Data) -> Publication? {
        let prefix = Data([0x42, 0x43, 0x4d, 0x52])
        var index = 0
        
        func readData(length: Int) -> Data? {
            guard index + length <= lockingScript.count else { return nil }
            defer { index += length }
            return lockingScript.subdata(in: index..<index + length)
        }
        
        func readLength(byteCount: Int) -> Int? {
            guard let data = readData(length: byteCount) else { return nil }
            var value = 0
            for (offset, byte) in data.enumerated() {
                value |= Int(byte) << (8 * offset)
            }
            return value
        }
        
        func readPushDataLength(opcode: UInt8) -> Int? {
            switch opcode {
            case 0x01...0x4b:
                return Int(opcode)
            case 0x4c:
                return readLength(byteCount: 1)
            case 0x4d:
                return readLength(byteCount: 2)
            case 0x4e:
                return readLength(byteCount: 4)
            default:
                return nil
            }
        }
        
        func readPushData() -> Data? {
            guard index < lockingScript.count else { return nil }
            let opcode = lockingScript[index]
            index += 1
            guard let length = readPushDataLength(opcode: opcode) else { return nil }
            return readData(length: length)
        }
        
        while index < lockingScript.count {
            let opcode = lockingScript[index]
            index += 1
            
            if opcode == 0x6a {
                guard let tag = readPushData() else { return nil }
                guard tag == prefix else { continue }
                guard let sha256 = readPushData(), sha256.count == 32 else { return nil }
                
                var uris: [String] = .init()
                while index < lockingScript.count {
                    guard let uriData = readPushData() else { return nil }
                    guard let uri = String(data: uriData, encoding: .utf8) else { return nil }
                    uris.append(uri)
                }
                
                return Publication(sha256: sha256, uris: uris)
            }
            
            guard let length = readPushDataLength(opcode: opcode) else { continue }
            guard index + length <= lockingScript.count else { return nil }
            index += length
        }
        
        return nil
    }
}
