import Foundation
import Testing
@testable import OpalBase

@Suite("Satoshi", .tags(.unit))
struct SatoshiTests {
    @Test("initialisation from integer")
    func testInitializeFromInteger() throws {
        let value = try Satoshi(42)
        #expect(value.uint64 == 42)
        guard let expected = Decimal(string: "0.00000042") else {
            #expect(Bool(false), "Failed to build expected Decimal literal")
            return
        }
        #expect(value.bch == expected)
    }
    
    @Test("addition respects maximum supply")
    func additionRespectsMaximumSupply() throws {
        let half = try Satoshi(Satoshi.maximumSatoshi / 2)
        let otherHalf = try Satoshi(Satoshi.maximumSatoshi / 2)
        let combined = try half + otherHalf
        #expect(combined.uint64 == Satoshi.maximumSatoshi)
        
        #expect(throws: Satoshi.Error.exceedsMaximumAmount) {
            _ = try combined + Satoshi(1)
        }
    }
    
    @Test("subtraction prevents negative results")
    func subtractionPreventsNegativeResults() throws {
        let initial = try Satoshi(10)
        let remainder = try initial - Satoshi(4)
        #expect(remainder.uint64 == 6)
        
        #expect(throws: Satoshi.Error.negativeResult) {
            _ = try Satoshi(1) - Satoshi(2)
        }
    }
}
