import Foundation
import Testing
@testable import OpalBase

@Suite("BlockHeader", .tags(.unit, .block))
struct BlockHeaderTests {
    @Test("decode rejects insufficient data")
    func testDecodeRejectsInsufficientData() {
        let validHeader = Data(repeating: 0x01, count: 80)
        let truncatedHeader = Data(validHeader.dropLast())
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try Block.Header.decode(from: truncatedHeader)
        }
    }
    
    @Test("decode round-trips encoded header")
    func testDecodeRoundTripsEncodedHeader() throws {
        let previousBlockHash = Data(repeating: 0x02, count: 32)
        let merkleRoot = Data(repeating: 0x03, count: 32)
        let header = Block.Header(
            version: 2,
            previousBlockHash: previousBlockHash,
            merkleRoot: merkleRoot,
            time: 1,
            bits: 0x1d00ffff,
            nonce: 4
        )
        
        let encoded = header.encode()
        let (decoded, bytesRead) = try Block.Header.decode(from: encoded)
        
        #expect(bytesRead == encoded.count)
        #expect(decoded.version == header.version)
        #expect(decoded.previousBlockHash == header.previousBlockHash)
        #expect(decoded.merkleRoot == header.merkleRoot)
        #expect(decoded.time == header.time)
        #expect(decoded.bits == header.bits)
        #expect(decoded.nonce == header.nonce)
    }
}
