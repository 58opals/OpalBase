// ReusablePaymentAddressCodecValidator.swift

import Testing
@testable import OpalBase

@Suite("Reusable payment address codec contract", .tags(.unit))
struct ReusablePaymentAddressCodecValidator {
    @Test("default codec refuses unverified paycode wire behavior")
    func refuseUnverifiedWireBehavior() throws {
        let codec = OpalBase.ReusablePaymentAddress.Codec()
        let address = try ReusablePaymentAddressFixtureData.makeAddress()

        #expect(throws: OpalBase.ReusablePaymentAddress.Error.specificationUnavailable) {
            _ = try codec.parse("rpa:placeholder")
        }
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.specificationUnavailable) {
            _ = try codec.encode(address)
        }
    }

    @Test("closure-backed codec establishes parse and encode boundary")
    func useClosureBackedCodec() throws {
        let address = try ReusablePaymentAddressFixtureData.makeAddress()
        let codec = OpalBase.ReusablePaymentAddress.Codec(
            parse: { paycode in
                #expect(paycode == "rpa:fixture")
                return address
            },
            encode: { encodedAddress in
                #expect(encodedAddress == address)
                return "rpa:fixture"
            }
        )

        #expect(try codec.parse("rpa:fixture") == address)
        #expect(try codec.encode(address) == "rpa:fixture")
    }
}
