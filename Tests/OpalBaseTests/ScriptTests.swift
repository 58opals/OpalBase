import XCTest
@testable import OpalBase

final class ScriptTests: XCTestCase {
    func testP2PKHDecoding() throws {
        let lockingScript = Data([0x76, 0xa9, 0x14] + Array(repeating: 0x01, count: 20) + [0x88, 0xac])
        let decodedScript = try Script.decode(lockingScript: lockingScript)
        
        switch decodedScript {
        case .p2pkh(let hash):
            XCTAssertEqual(hash.data, Data(repeating: 0x01, count: 20))
        default:
            XCTFail("Failed to decode P2PKH script")
        }
    }
}
