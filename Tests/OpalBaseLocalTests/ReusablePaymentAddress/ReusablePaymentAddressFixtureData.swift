// ReusablePaymentAddressFixtureData.swift

import Foundation
@testable import OpalBase

enum ReusablePaymentAddressFixtureData {
    static let cashCodeMainnet =
        "cashcode:qygqyh9a7pjxuhd5a23e3um97t485r3agxdhuqesuwwwj27aah9vf7duq0egwu7zm96j3z7868fqtsm5segmqa0mcessukxdmmkalrcegpd2sqqqqqqq5r40kskr"
    static let cashCodeTestnet =
        "cashcodetest:q5gqyh9a7pjxuhd5a23e3um97t485r3agxdhuqesuwwwj27aah9vf7duq0egwu7zm96j3z7868fqtsm5segmqa0mcessukxdmmkalrcegpd2sqqqqqqqjltpqdmm"
    static let legacyPaycodeMainnet =
        "paycode:qygqyh9a7pjxuhd5a23e3um97t485r3agxdhuqesuwwwj27aah9vf7duq0egwu7zm96j3z7868fqtsm5segmqa0mcessukxdmmkalrcegpd2sqqqqqqq6r7mr3j2"
    static let legacyPaycodeTestnet =
        "paycodetest:q5gqyh9a7pjxuhd5a23e3um97t485r3agxdhuqesuwwwj27aah9vf7duq0egwu7zm96j3z7868fqtsm5segmqa0mcessukxdmmkalrcegpd2sqqqqqqqww5uhs6j"
    static let incompatibleCashAddrFraming =
        "paycode:qqq3qqjuhhcxgmjakn428x8nvhew57sw84qeklsrxr3ee6ftmhku438ehspl9pmnctvh22ytclgaypwrwjr9rvr4l0rxzrjceh0wmhu0r9q942qqqqqqqv6zdr9hy"
    static let positiveTransactionHex =
        "02000000018967452301efcdab8967452301efcdab8967452301efcdab8967452301efcdab00000000644194de9ad0201051f6e002f5197a4e94bfc91c0a77aad9302caf0501e1f20671e680961e2259d1363d1edf05b8a3387d4074998ef91a9ff2cbbb5c9f02b7e7bdc341210362d14dab4150bf497402fdc45a215e10dcb01c354959b10cfe31c7e9d87ff33dfeffffff0280380100000000003cef8967452301efcdab8967452301efcdab8967452301efcdab8967452301efcdab100176a9143d61c96622930aa8890653535c41c359677d4fed88ac384a0000000000001976a914e7616ca66fd2937f140c57a40c6ce9b4b23fc82e88ac00000000"
    static let prefixMissTransactionHex =
        "02000000018967452301efcdab8967452301efcdab8967452301efcdab8967452301efcdab0000000064410687ad7e4a128884e16511fa27757f8126f40f40091c1b85cae96f16871838b4cd779e7283cd2662bf50678aa9975f597fe898b4199db9e69ead64d413e6f6b341210362d14dab4150bf497402fdc45a215e10dcb01c354959b10cfe31c7e9d87ff33dfeffffff0280380100000000003cef8967452301efcdab8967452301efcdab8967452301efcdab8967452301efcdab100176a9143d61c96622930aa8890653535c41c359677d4fed88ac384a0000000000001976a914e7616ca66fd2937f140c57a40c6ce9b4b23fc82e88ac00000000"
    static let uncompressedInputTransactionHex =
        "02000000018967452301efcdab8967452301efcdab8967452301efcdab8967452301efcdab000000008441c4f446f2ab5576cb4ae2e3f594893445a217154d28652df0db0a18c030a0cc853fee65f85fbb1762b2ab63271f7d56f1ee367028f6e55a06d5c18c62303b839441410462d14dab4150bf497402fdc45a215e10dcb01c354959b10cfe31c7e9d87ff33d80fc06bd8cc5b01098088a1950eed0db01aa132967ab472235f5642483b25eaffeffffff0280380100000000003cef8967452301efcdab8967452301efcdab8967452301efcdab8967452301efcdab100176a9143d61c96622930aa8890653535c41c359677d4fed88ac384a0000000000001976a914e7616ca66fd2937f140c57a40c6ce9b4b23fc82e88ac00000000"
    static let positiveTransactionID =
        "f3f3c50b93b90f5e7b9ca68fe01048f8222f0f98011e264242f49c543d9cca4d"
    static let matchingLockingScript =
        "76a9143d61c96622930aa8890653535c41c359677d4fed88ac"
    static let childCompressedPublicKey =
        "039f3c77288d6e9c76a599f14c3f72bbd9f87d80fc12263e057eb234b435d05979"
    static let senderCompressedPublicKey =
        "0362d14dab4150bf497402fdc45a215e10dcb01c354959b10cfe31c7e9d87ff33d"

    static let applicationPayload = try! Data(
        hexadecimalString:
            "0110025cbdf0646e5db4eaa398f365f2ea7a0e3d419b7e0330e39ce92bddedcac4f9bc03f28773c2d975288bc7d1d205c3748651b075fbc6610e58cddeeddf8f19405aa800000000"
    )

    static func makePublicKey(byte: UInt8 = 1) throws -> OpalBase.Key.PublicKey {
        try OpalBase.Key.PublicKey(privateKeyData: Data(repeating: byte, count: 32))
    }

    static func makeScanPublicKey() throws -> OpalBase.Key.PublicKey {
        try OpalBase.Key.PublicKey(
            compressedData: Data(
                hexadecimalString:
                    "025cbdf0646e5db4eaa398f365f2ea7a0e3d419b7e0330e39ce92bddedcac4f9bc"
            )
        )
    }

    static func makeSpendPublicKey() throws -> OpalBase.Key.PublicKey {
        try OpalBase.Key.PublicKey(
            compressedData: Data(
                hexadecimalString:
                    "03f28773c2d975288bc7d1d205c3748651b075fbc6610e58cddeeddf8f19405aa8"
            )
        )
    }

    static func makeScanSigningKey() throws -> OpalBase.Key.SigningKey {
        try makeSigningKey(scalar: 7)
    }

    static func makeSpendSigningKey() throws -> OpalBase.Key.SigningKey {
        try makeSigningKey(scalar: 13)
    }

    static func makeSenderSigningKey() throws -> OpalBase.Key.SigningKey {
        try makeSigningKey(scalar: 37)
    }

    static func makeSigningKey(
        scalar: UInt8
    ) throws -> OpalBase.Key.SigningKey {
        var rawRepresentation = Data(repeating: 0, count: 31)
        rawRepresentation.append(scalar)
        return try OpalBase.Key.SigningKey(
            rawRepresentation: rawRepresentation
        )
    }

    static func decodeTransaction(
        hexadecimalString: String
    ) throws -> (
        transaction: OpalBase.Transaction,
        bytesRead: Int,
        data: Data
    ) {
        let data = try Data(hexadecimalString: hexadecimalString)
        let decoded = try OpalBase.Transaction.decode(from: data)
        return (decoded.transaction, decoded.bytesRead, data)
    }

    static func makeTransactionHash(byte: UInt8 = 1) -> OpalBase.Transaction.Hash {
        OpalBase.Transaction.Hash(naturalOrder: Data(repeating: byte, count: 32))
    }

    static func makeOutpoint(byte: UInt8 = 1, outputIndex: UInt32 = 0) -> OpalBase.Transaction.Outpoint {
        OpalBase.Transaction.Outpoint(
            transactionHash: makeTransactionHash(byte: byte),
            outputIndex: outputIndex
        )
    }

    static func makeAddress(
        network: OpalBase.Network.Environment = .mainnet
    ) throws -> OpalBase.ReusablePaymentAddress {
        OpalBase.ReusablePaymentAddress(
            cashCodeV1For: network,
            scanPublicKey: try makeScanPublicKey(),
            spendPublicKey: try makeSpendPublicKey()
        )
    }

    static func makeEncodedIdentifier(
        scheme: String,
        payload: Data
    ) throws -> String {
        let payloadFiveBitValues = try BitConversion.convertBits(
            [UInt8](payload),
            from: 8,
            to: 5,
            pad: true
        )
        let prefixValues = scheme.utf8.map { $0 & 0x1f }
        let checksumValue = try OpalCryptoAdapter.computePolymod(
            prefixValues
            + [0]
            + payloadFiveBitValues
            + [UInt8](repeating: 0, count: 8)
        )
        let checksum: [UInt8] = (0..<8).map { index in
            let shift = UInt64(5 * (7 - index))
            return UInt8((checksumValue >> shift) & 0x1f)
        }
        let encodedPayload = try OpalCryptoAdapter.encodeBase32(
            Data(payloadFiveBitValues + checksum),
            interpretedAsFiveBitValues: true
        )
        return "\(scheme):\(encodedPayload)"
    }

}
