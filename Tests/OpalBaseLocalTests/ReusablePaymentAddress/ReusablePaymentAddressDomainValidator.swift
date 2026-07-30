// ReusablePaymentAddressDomainValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Reusable payment address domain contracts", .tags(.unit))
struct ReusablePaymentAddressDomainValidator {
    @Test("Cash Code v1 field contract fixes profile policy")
    func preserveCashCodeV1Fields() throws {
        let address = try ReusablePaymentAddressFixtureData.makeAddress()

        #expect(address.profile == .cashCodeV1)
        #expect(address.network == .mainnet)
        #expect(address.prefixLength == .sixteenBits)
        #expect(address.expiration == .never)
        #expect(address.scanPublicKey != address.spendPublicKey)
    }

    @Test("prefix length exposes only protocol-supported bit counts")
    func exposeSupportedPrefixLengths() {
        #expect(OpalBase.ReusablePaymentAddress.PrefixLength(rawValue: 0) == nil)
        #expect(OpalBase.ReusablePaymentAddress.PrefixLength(rawValue: 4) == .fourBits)
        #expect(OpalBase.ReusablePaymentAddress.PrefixLength(rawValue: 8) == .eightBits)
        #expect(OpalBase.ReusablePaymentAddress.PrefixLength(rawValue: 12) == .twelveBits)
        #expect(OpalBase.ReusablePaymentAddress.PrefixLength(rawValue: 16) == .sixteenBits)
        #expect(OpalBase.ReusablePaymentAddress.PrefixLength(rawValue: 20) == nil)
    }

    @Test("expiration distinguishes no expiry from legacy Unix time")
    func distinguishExpirationValues() {
        #expect(OpalBase.ReusablePaymentAddress.Expiration.never != .unixTime(0))
        #expect(OpalBase.ReusablePaymentAddress.Expiration.unixTime(1_700_000_000) != .never)
    }
}
