import Testing
import Foundation
@testable import OpalBase

@Suite("DerivationPath Account Tests")
struct DerivationPathAccountTests {}

extension DerivationPathAccountTests {
    @Test func testSequentialIncrease() throws {
        var account = try DerivationPath.Account(rawIndexInteger: 0)
        for expected in 1...10 {
            try account.increase()
            #expect(account.getUnhardenedIndex() == UInt32(expected), "Account index should be \(expected)")
        }
    }
    
    @Test func testIncreaseOverflow() throws {
        var account = try DerivationPath.Account(rawIndexInteger: 0x7FFFFFFE)
        try account.increase()
        #expect(account.getUnhardenedIndex() == 0x7FFFFFFF, "Account index should reach max value")
        
        do {
            try account.increase()
            #expect(Bool(false), "Increasing beyond max should throw")
        } catch DerivationPath.Error.indexOverflow {
            #expect(true, "Expected indexOverflow error")
        }
    }
}
