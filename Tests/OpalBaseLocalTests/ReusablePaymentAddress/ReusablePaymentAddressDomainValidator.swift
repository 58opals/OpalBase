// ReusablePaymentAddressDomainValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Reusable payment address domain contracts", .tags(.unit))
struct ReusablePaymentAddressDomainValidator {
    @Test("paycode field contract preserves public keys and network")
    func preservePaycodeFields() throws {
        let address = try ReusablePaymentAddressFixtureData.makeAddress()

        #expect(address.version.rawValue == 0)
        #expect(address.network == .mainnet)
        #expect(address.prefixLength.bitCount == 12)
        #expect(!address.expiration.isFinite)
        #expect(address.scanPublicKey != address.spendPublicKey)
    }

    @Test("prefix length rejects negative bit counts")
    func rejectNegativePrefixLength() {
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidPrefixLength(-1)) {
            _ = try OpalBase.ReusablePaymentAddress.PrefixLength(bitCount: -1)
        }
    }

    @Test("input hash prefix is bounded by supplied hash bits")
    func validateInputHashPrefixAgainstHashLength() throws {
        let valid = try OpalBase.ReusablePaymentAddress.InputHashPrefix(
            hash: Data([0xAA]),
            prefixLength: .init(bitCount: 8)
        )
        #expect(valid.hash == Data([0xAA]))

        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidHashPrefix) {
            _ = try OpalBase.ReusablePaymentAddress.InputHashPrefix(
                hash: Data([0xAA]),
                prefixLength: .init(bitCount: 9)
            )
        }
    }

    @Test("expiration reports block-height status without accepting negative heights")
    func validateExpirationBlockHeight() throws {
        let expiration = try OpalBase.ReusablePaymentAddress.Expiration(blockHeight: 200)

        #expect(expiration.isFinite)
        #expect(!expiration.hasExpired(atBlockHeight: 199))
        #expect(expiration.hasExpired(atBlockHeight: 200))
        #expect(!OpalBase.ReusablePaymentAddress.Expiration.never.hasExpired(atBlockHeight: Int.max))

        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidBlockHeight(-1)) {
            _ = try OpalBase.ReusablePaymentAddress.Expiration(blockHeight: -1)
        }
    }

    @Test("receive candidates expose transaction outpoints")
    func exposeReceiveCandidateOutpoint() throws {
        let candidate = try ReusablePaymentAddressFixtureData.makeReceiveCandidate()

        #expect(candidate.outpoint.transactionHash == candidate.transactionHash)
        #expect(candidate.outpoint.outputIndex == candidate.outputIndex)
        #expect(candidate.inputMetadata.count == 1)
    }
}
