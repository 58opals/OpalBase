import Foundation
import Testing
@testable import OpalBase

@Suite("Opal Base Tests")
struct OpalBaseTests {}

extension OpalBaseTests {
    @Test func testPrint() {
        print("Hello, Bitcoin Cash.")
    }
}
