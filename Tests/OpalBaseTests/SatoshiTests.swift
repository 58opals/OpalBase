import Foundation
import Testing
@testable import OpalBase

@Suite("Satoshi Tests")
struct SatoshiTests {}

extension SatoshiTests {
    @Test func testInitFromBCHRounding() throws {
        let value1 = try Satoshi(bch: 0.000000004)
        #expect(value1.uint64 == 0, "Rounding down should result in 0 satoshis")
        
        let value2 = try Satoshi(bch: 0.000000005)
        #expect(value2.uint64 == 1, "0.000000005 BCH should round to 1 satoshi")
        
        let value3 = try Satoshi(bch: 0.000000016)
        #expect(value3.uint64 == 2, "0.000000015 BCH should round to 2 satoshis")
    }
    
    @Test func testInitFromBCHMaximum() throws {
        let maxBCHValue = Double(Satoshi.maximumBCH)
        let satoshi = try Satoshi(bch: maxBCHValue)
        #expect(satoshi.uint64 == Satoshi.maximumSatoshi, "Maximum BCH should convert to maximum satoshis")
    }
    
    @Test func testInitFromBCHBeyondMaximumThrows() throws {
        let beyondMax = Double(Satoshi.maximumBCH) + 1
        do {
            _ = try Satoshi(bch: beyondMax)
            #expect(Bool(false), "Initializing beyond maximum should throw")
        } catch Satoshi.Error.exceedsMaximumAmount {
            #expect(true, "Expected exceedsMaximumAmount error")
        } catch {
            #expect(Bool(false), "Unexpected error type: \(error)")
        }
    }
}
