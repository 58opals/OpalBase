import Foundation
import Testing
@testable import OpalBase

@Suite("Data extensions", .tags(.unit))
struct DataExtensionsTests {
    @Test("reversedData matches reverse iteration")
    func testReversedDataMatchesStandardReverse() throws {
        let bytes = Array(0...255).map(UInt8.init)
        let data = Data(bytes)

        let reversed = data.reversedData
        let expected = Data(bytes.reversed())

        #expect(reversed == expected)
    }
}
