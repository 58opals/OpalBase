// SatoshiValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Satoshi", .tags(.unit))
struct SatoshiValidator {
    @Test("initialization from integer")
    func initializeFromInteger() throws {
        let value = try OpalBase.Satoshi(42)
        #expect(value.uint64 == 42)
        let expected = try #require(Decimal(string: "0.00000042"))
        #expect(value.bch == expected)
    }
    
    @Test("addition respects maximum supply")
    func additionRespectsMaximumSupply() throws {
        let half = try OpalBase.Satoshi(OpalBase.Satoshi.maximumSatoshi / 2)
        let otherHalf = try OpalBase.Satoshi(OpalBase.Satoshi.maximumSatoshi / 2)
        let combined = try half + otherHalf
        #expect(combined.uint64 == OpalBase.Satoshi.maximumSatoshi)
        
        #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try combined + OpalBase.Satoshi(1)
        }
    }
    
    @Test("multiplication scales value by integer")
    func multiplicationScalesValueByInteger() throws {
        let initial = try OpalBase.Satoshi(25)
        let multiplied = try initial * 4
        #expect(multiplied.uint64 == 100)
    }
    
    @Test("multiplication enforces maximum supply")
    func multiplicationEnforcesMaximumSupply() throws {
        let half = try OpalBase.Satoshi(OpalBase.Satoshi.maximumSatoshi / 2)
        let doubled = try half * 2
        #expect(doubled.uint64 == OpalBase.Satoshi.maximumSatoshi)
        
        let maximum = try OpalBase.Satoshi(OpalBase.Satoshi.maximumSatoshi)
        #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try maximum * 2
        }
    }

    @Test("multiplication rejects near-maximum overflow")
    func multiplicationRejectsNearMaximumOverflow() throws {
        let nearlyMaximum = try OpalBase.Satoshi(OpalBase.Satoshi.maximumSatoshi - 1)
        
        #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try nearlyMaximum * 2
        }
    }

    @Test("subtraction prevents negative results")
    func subtractionPreventsNegativeResults() throws {
        let initial = try OpalBase.Satoshi(10)
        let remainder = try initial - OpalBase.Satoshi(4)
        #expect(remainder.uint64 == 6)
        
        #expect(throws: OpalBase.Satoshi.Error.negativeResult) {
            _ = try OpalBase.Satoshi(1) - OpalBase.Satoshi(2)
        }
    }
    
    @Test("division validates divisor")
    func divisionValidatesDivisor() throws {
        let ten = try OpalBase.Satoshi(10)
        let half = try ten / 2
        #expect(half.uint64 == 5)
        
        #expect(throws: OpalBase.Satoshi.Error.divisionByZero) {
            _ = try ten / 0
        }
    }
    
    @Test("initialization from BCH rejects negative values")
    func initializeFromBCHRejectsNegativeValues() throws {
        #expect(throws: OpalBase.Satoshi.Error.negativeResult) {
            _ = try OpalBase.Satoshi(bch: -0.0001)
        }
    }
    
    @Test("initialization from BCH rejects fractional satoshi")
    func initializeFromBCHRejectsFractionalSatoshi() throws {
        #expect(throws: OpalBase.Satoshi.Error.invalidPrecision) {
            _ = try OpalBase.Satoshi(bch: 0.000000015)
        }
    }

    @Test("initialization from large BCH rejects fractional satoshi")
    func initializeFromLargeBCHRejectsFractionalSatoshi() throws {
        #expect(throws: OpalBase.Satoshi.Error.invalidPrecision) {
            _ = try OpalBase.Satoshi(bch: 20_000_000.000000004)
        }

        let validLargeValue = try OpalBase.Satoshi(bch: 20_000_000.00000002)
        #expect(validLargeValue.uint64 == 2_000_000_000_000_002)
    }

    @Test("initialization from BCH rejects values above maximum supply before rounding")
    func initializeFromBCHRejectsValuesAboveMaximumSupplyBeforeRounding() throws {
        #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try OpalBase.Satoshi(bch: 21_000_000.000000004)
        }
    }
}
