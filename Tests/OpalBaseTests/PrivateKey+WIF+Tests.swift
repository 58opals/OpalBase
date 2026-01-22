import Foundation
import Testing
@testable import OpalBase

@Suite("PrivateKey.WalletImportFormat", .tags(.unit))
struct PrivateKeyWalletImportFormatTests {
    @Test("wallet import format encodes compressed private key")
    func testEncodeCompressedWalletImportFormat() throws {
        let privateKeyData = Data(repeating: 0x00, count: 31) + Data([0x01])
        let privateKey = try PrivateKey(data: privateKeyData)
        let expectedCompressedWalletImportFormat = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
        
        #expect(
            privateKey.makeWalletImportFormat(compression: .compressed) == expectedCompressedWalletImportFormat
        )
    }
    
    @Test("wallet import format encodes uncompressed private key")
    func testEncodeUncompressedWalletImportFormat() throws {
        let privateKeyData = Data(repeating: 0x00, count: 31) + Data([0x01])
        let privateKey = try PrivateKey(data: privateKeyData)
        let expectedCompressedWalletImportFormat = "5HpHagT65TZzG1PH3CSu63k8DbpvD8s5ip4nEB3kEsreAnchuDf"
        
        #expect(
            privateKey.makeWalletImportFormat(compression: .uncompressed) == expectedCompressedWalletImportFormat
        )
    }
    
    @Test("wallet import format decoding matches compressed key")
    func testDecodeCompressedWalletImportFormat() throws {
        let expectedCompressedWalletImportFormat = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
        let privateKeyData = Data(repeating: 0x00, count: 31) + Data([0x01])
        
        let decodedPrivateKey = try PrivateKey(
            wif: expectedCompressedWalletImportFormat,
            expectedCompression: .compressed
        )
        
        #expect(decodedPrivateKey.rawData == privateKeyData)
    }
}
