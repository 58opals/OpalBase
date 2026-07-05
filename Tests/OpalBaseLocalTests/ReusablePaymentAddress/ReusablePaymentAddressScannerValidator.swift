// ReusablePaymentAddressScannerValidator.swift

import Testing
@testable import OpalBase

@Suite("Reusable payment address scanner contract", .tags(.unit))
struct ReusablePaymentAddressScannerValidator {
    @Test("scanner closure can promote a candidate to a receive result")
    func promoteCandidateToReceiveResult() throws {
        let address = try ReusablePaymentAddressFixtureData.makeAddress()
        let candidate = try ReusablePaymentAddressFixtureData.makeReceiveCandidate()
        let receivingPublicKey = try ReusablePaymentAddressFixtureData.makePublicKey(byte: 6)
        let scanner = OpalBase.ReusablePaymentAddress.Scanner { scannedCandidate, scannedAddress in
            #expect(scannedCandidate == candidate)
            #expect(scannedAddress == address)
            return OpalBase.ReusablePaymentAddress.ReceiveResult(
                reusablePaymentAddress: scannedAddress,
                candidate: scannedCandidate,
                receivingPublicKey: receivingPublicKey
            )
        }

        let result = try scanner.scan(candidate, for: address)

        #expect(result?.candidate == candidate)
        #expect(result?.reusablePaymentAddress == address)
        #expect(result?.receivingPublicKey == receivingPublicKey)
    }

    @Test("scanner closure can leave an unmatched candidate nil")
    func returnNilForUnmatchedCandidate() throws {
        let scanner = OpalBase.ReusablePaymentAddress.Scanner { _, _ in nil }

        let result = try scanner.scan(
            ReusablePaymentAddressFixtureData.makeReceiveCandidate(),
            for: ReusablePaymentAddressFixtureData.makeAddress()
        )

        #expect(result == nil)
    }
}
