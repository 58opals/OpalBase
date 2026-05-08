// OpalBase.CashTokens.BCMR.Client+Publication.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
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
        var index = lockingScript.startIndex
        
        func readData(length: Int) -> Data? {
            guard length >= 0,
                  let nextIndex = lockingScript.index(index, offsetBy: length, limitedBy: lockingScript.endIndex)
            else { return nil }
            defer { index = nextIndex }
            return Data(lockingScript[index..<nextIndex])
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
            guard index < lockingScript.endIndex else { return nil }
            let opcode = lockingScript[index]
            index = lockingScript.index(after: index)
            guard let length = readPushDataLength(opcode: opcode) else { return nil }
            return readData(length: length)
        }
        
        guard index < lockingScript.endIndex, lockingScript[index] == 0x6a else { return nil }
        index = lockingScript.index(after: index)

        guard let tag = readPushData(), tag == prefix else { return nil }
        guard let sha256 = readPushData(), sha256.count == 32 else { return nil }

        var uris: [String] = .init()
        while index < lockingScript.endIndex {
            guard let uriData = readPushData() else { return nil }
            guard let uri = String(data: uriData, encoding: .utf8) else { return nil }
            uris.append(uri)
        }
        
        guard !uris.isEmpty else { return nil }

        return Publication(sha256: sha256, uris: uris)
    }
}
