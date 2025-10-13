import Foundation
import Testing
@testable import OpalBase

@Suite("Satoshi arithmetic", .tags(.unit, .core))
struct SatoshiArithmeticSuite {
    @Test("throws when scaling beyond UInt64", .tags(.unit, .core))
    func throwsWhenMultiplicationOverflows() throws {
        let amount = try Satoshi(2)

        #expect(throws: Satoshi.Error.exceedsMaximumAmount) {
            _ = try amount * UInt64.max
        }
    }
}
