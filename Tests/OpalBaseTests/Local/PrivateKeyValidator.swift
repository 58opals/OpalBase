// PrivateKeyValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.PrivateKey", .tags(.unit, .key))
struct PrivateKeyValidator {
    @Test("wif encodes compressed private key")
    func encodeCompressedWif() throws {
        let privateKeyData = Data(repeating: 0x00, count: 31) + Data([0x01])
        let privateKey = try OpalBase.PrivateKey(data: privateKeyData)
        let expectedWalletImportFormat = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
        
        #expect(privateKey.wif == expectedWalletImportFormat)
    }
    
    @Test("wif decoding matches compressed key")
    func decodeCompressedWif() throws {
        let expectedWalletImportFormat = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
        let privateKeyData = Data(repeating: 0x00, count: 31) + Data([0x01])
        
        let decodedPrivateKey = try OpalBase.PrivateKey(wif: expectedWalletImportFormat)
        
        #expect(decodedPrivateKey.rawData == privateKeyData)
    }
}

