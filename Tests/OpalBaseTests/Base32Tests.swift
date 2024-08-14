import XCTest
@testable import OpalBase

final class Base32Tests: XCTestCase {
    func testBase32EncodingDecoding() throws {
        let testCases: [(data: Data, expectedEncoded: String, interpretedAs5Bit: Bool)] = [
            (Data([0x00]), "q", true),
            (Data([0x01]), "p", true),
            (Data([0x02, 0x04]), "zy", true),
            (Data([0x0f, 0xff]), "rll", false),
            (Data([0x00, 0x01, 0x02]), "qpz", true),
            (Data([0x10, 0x20, 0x30]), "pqgps", false),
            (Data([0xff, 0xee, 0xdd, 0xcc]), "rl7ahwv", false),
            (Data([0x00, 0x00, 0x01]), "qqp", true)
        ]

        for (index, testCase) in testCases.enumerated() {
            let encoded = Base32.encode(testCase.data, interpretedAs5Bit: testCase.interpretedAs5Bit)
            let decoded = try Base32.decode(encoded, interpretedAs5Bit: testCase.interpretedAs5Bit)
            
            // Verify that encoded string matches expected encoded string
            XCTAssertEqual(encoded, testCase.expectedEncoded, "Encoding failed for test case \(index + 1): expected \(testCase.expectedEncoded), but got \(encoded)")
            
            // Verify that decoding the encoded string returns the original data
            XCTAssertEqual(decoded, testCase.data, "Decoding failed for test case \(index + 1): expected \(testCase.data), but got \(decoded)")
        }
    }
}
