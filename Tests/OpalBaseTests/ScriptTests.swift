import Foundation
import Testing
@testable import OpalBase

@Suite("Script Tests")
struct ScriptTests {}

extension ScriptTests {
    @Test func testP2PKHDecoding() throws {
        let data = Data(Array(repeating: 0x01, count: 20))
        let lockingScript = Data([0x76, 0xa9, 0x14]) + data + Data([0x88, 0xac])
        let decodedScript = try Script.decode(lockingScript: lockingScript)
        
        switch decodedScript {
        case .p2pkh_OPCHECKSIG(let hash):
            #expect(hash.data == data, "Decoded P2PKH hash does not match expected data.")
        default:
            #expect(Bool(false), "Failed to decode P2PKH script as expected.")
        }
    }
}
