import Foundation
import Testing
@testable import OpalBase

@Suite("Satoshi", .tags(.unit))
struct SatoshiValidator {
    @Test("initialization from integer")
    func initializeFromInteger() throws {
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
    
    @Test("multiplication scales value by integer")
    func multiplicationScalesValueByInteger() throws {
        let initial = try Satoshi(25)
        let multiplied = try initial * 4
        #expect(multiplied.uint64 == 100)
    }
    
    @Test("multiplication enforces maximum supply")
    func multiplicationEnforcesMaximumSupply() throws {
        let half = try Satoshi(Satoshi.maximumSatoshi / 2)
        let doubled = try half * 2
        #expect(doubled.uint64 == Satoshi.maximumSatoshi)
        
        let maximum = try Satoshi(Satoshi.maximumSatoshi)
        #expect(throws: Satoshi.Error.exceedsMaximumAmount) {
            _ = try maximum * 2
        }
    }
    
    @Test("multiplication scales smaller values")
    func multiplicationScalesSmallerValues() throws {
        let base = try Satoshi(3)
        let product = try base * UInt64(4)
        #expect(product.uint64 == 12)
    }
    
    @Test("multiplication respects maximum supply")
    func multiplicationRespectsMaximumSupply1() throws {
        let nearlyMaximum = try Satoshi(Satoshi.maximumSatoshi - 1)
        
        #expect(throws: Satoshi.Error.exceedsMaximumAmount) {
            _ = try nearlyMaximum * 2
        }
    }
    
    @Test("multiplication respects maximum supply")
    func multiplicationRespectsMaximumSupply2() throws {
        let maximum = try Satoshi(Satoshi.maximumSatoshi)
        
        #expect(throws: Satoshi.Error.exceedsMaximumAmount) {
            _ = try maximum * UInt64(2)
        }
    }
    
    @Test("multiplication of a small value")
    func multiplySmallValueByInteger() throws {
        let value = try Satoshi(5)
        let product = try value * 3
        #expect(product.uint64 == 15)
    }
    
    @Test("multiplication exceeding the maximum supply")
    func multiplyNearMaximumValueThrows() throws {
        let nearMaximum = try Satoshi(Satoshi.maximumSatoshi - 1)
        
        #expect(throws: Satoshi.Error.exceedsMaximumAmount) {
            _ = try nearMaximum * 2
        }
    }
    
    @Test("multiplication respects maximum supply")
    func multiplicationRespectsMaximumSupply() throws {
        let base = try Satoshi(Satoshi.maximumSatoshi / 2)
        let doubled = try base * 2
        #expect(doubled.uint64 == Satoshi.maximumSatoshi)
        
        #expect(throws: Satoshi.Error.exceedsMaximumAmount) {
            _ = try Satoshi(Satoshi.maximumSatoshi) * 2
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
    
    @Test("division validates divisor")
    func divisionValidatesDivisor() throws {
        let ten = try Satoshi(10)
        let half = try ten / 2
        #expect(half.uint64 == 5)
        
        #expect(throws: Satoshi.Error.divisionByZero) {
            _ = try ten / 0
        }
    }
    
    @Test("division handles zero and normal results")
    func divisionHandlesZeroAndNormalResults() throws {
        let initial = try Satoshi(100)
        let halved = try initial / 2
        #expect(halved.uint64 == 50)
        
        #expect(throws: Satoshi.Error.divisionByZero) {
            _ = try initial / 0
        }
    }
    
    @Test("initialization from BCH rejects negative values")
    func initializeFromBCHRejectsNegativeValues() throws {
        #expect(throws: Satoshi.Error.negativeResult) {
            _ = try Satoshi(bch: -0.0001)
        }
    }
    
    @Test("initialization from BCH rejects fractional satoshi")
    func initializeFromBCHRejectsFractionalSatoshi() throws {
        #expect(throws: Satoshi.Error.invalidPrecision) {
            _ = try Satoshi(bch: 0.000000015)
        }
    }
}
