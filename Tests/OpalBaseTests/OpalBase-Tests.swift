import Testing
import Foundation
@testable import OpalBase

@Suite("Opal Base")
struct OpalBaseTests {}

extension OpalBaseTests {
    @Test func testPrint() {
        print("Hello, Bitcoin Cash.")
    }
}
