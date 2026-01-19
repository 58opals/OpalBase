import Foundation
import Testing
@testable import OpalBase

@Suite("Base58", .tags(.unit, .coding))
struct Base58Tests {
    struct LinearCongruentialGenerator {
        private var state: UInt64
        
        init(seed: UInt64) {
            self.state = seed
        }
        
        mutating func nextValue() -> UInt64 {
            state = 2862933555777941757 &* state &+ 3037000493
            return state
        }
        
        mutating func makeBytes(count: Int) -> [UInt8] {
            var bytes: [UInt8] = .init()
            bytes.reserveCapacity(count)
            for _ in 0..<count {
                bytes.append(UInt8(truncatingIfNeeded: nextValue()))
            }
            return bytes
        }
    }
    
    @Test("round-trips payloads with leading zeroes")
    func testRoundTripPayloadsWithLeadingZeroes() {
        var generator = LinearCongruentialGenerator(seed: 0x1f2e3d4c5b6a7980)
        let lengths = [0, 1, 2, 3, 8, 12, 16, 24, 32, 48, 64]
        
        for (index, length) in lengths.enumerated() {
            let leadingZeroCount = index % 4
            let payloadBytes = generator.makeBytes(count: length)
            let payload = Data(repeating: 0, count: leadingZeroCount) + Data(payloadBytes)
            
            let encoded = Base58.encode(payload)
            let decoded = Base58.decode(encoded)
            
            #expect(decoded == payload)
        }
    }
    
    @Test("encodes and decodes known wallet import format vector")
    func testEncodesAndDecodesKnownWalletImportFormatVector() throws {
        let privateKeyData = Data(repeating: 0, count: 31) + Data([0x01])
        let privateKey = try PrivateKey(data: privateKeyData)
        let expectedWalletImportFormat = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
        
        let encodedWalletImportFormat = privateKey.wif
        let decodedPrivateKey = try PrivateKey(wif: expectedWalletImportFormat)
        
        #expect(encodedWalletImportFormat == expectedWalletImportFormat)
        #expect(decodedPrivateKey.rawData == privateKey.rawData)
    }
}
