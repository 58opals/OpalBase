import Foundation
import Testing
@testable import OpalBase

@Suite("PrivateKey", .tags(.unit, .key))
struct PrivateKeyTests {
    @Test("wif encodes compressed private key")
    func testEncodeCompressedWif() throws {
        let privateKeyData = Data(repeating: 0x00, count: 31) + Data([0x01])
        let privateKey = try PrivateKey(data: privateKeyData)
        let expectedWalletImportFormat = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
        
        #expect(privateKey.wif == expectedWalletImportFormat)
    }
    
    @Test("wif decoding matches compressed key")
    func testDecodeCompressedWif() throws {
        let expectedWalletImportFormat = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
        let privateKeyData = Data(repeating: 0x00, count: 31) + Data([0x01])
        
        let decodedPrivateKey = try PrivateKey(wif: expectedWalletImportFormat)
        
        #expect(decodedPrivateKey.rawData == privateKeyData)
    }
}
