// OpalBase+ReusablePaymentAddress+Codec.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct Codec: Sendable {
        private static let checksumSymbolCount = 8
        private static let payloadByteCount = 72
        private static let mainnetVersion: UInt8 = 1
        private static let testNetworkVersion: UInt8 = 5

        public init() {}

        public func parse(
            _ encodedIdentifier: String,
            network: OpalBase.Network.Environment
        ) throws -> OpalBase.ReusablePaymentAddress {
            guard encodedIdentifier == encodedIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                  !encodedIdentifier.isEmpty
            else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
            }

            let hasLowercase = encodedIdentifier.contains { $0.isLetter && $0.isLowercase }
            let hasUppercase = encodedIdentifier.contains { $0.isLetter && $0.isUppercase }
            guard !(hasLowercase && hasUppercase) else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
            }

            let normalizedIdentifier = encodedIdentifier.lowercased()
            let components = normalizedIdentifier.split(
                separator: ":",
                omittingEmptySubsequences: false
            )
            guard components.count == 2,
                  !components[0].isEmpty,
                  !components[1].isEmpty
            else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
            }

            let scheme = String(components[0])
            let encodedPayload = String(components[1])
            let profile: OpalBase.ReusablePaymentAddress.Profile
            let expectedVersion: UInt8
            switch (scheme, network) {
            case ("cashcode", .mainnet):
                profile = .cashCodeV1
                expectedVersion = Self.mainnetVersion
            case ("cashcodetest", .testnet),
                 ("cashcodetest", .chipnet):
                profile = .cashCodeV1
                expectedVersion = Self.testNetworkVersion
            case ("paycode", .mainnet):
                profile = .legacyElectronCash
                expectedVersion = Self.mainnetVersion
            case ("paycodetest", .testnet),
                 ("paycodetest", .chipnet):
                profile = .legacyElectronCash
                expectedVersion = Self.testNetworkVersion
            case ("cashcode", _),
                 ("cashcodetest", _),
                 ("paycode", _),
                 ("paycodetest", _):
                throw OpalBase.ReusablePaymentAddress.Error.networkMismatch
            default:
                throw OpalBase.ReusablePaymentAddress.Error.unsupportedScheme
            }

            let combinedFiveBitValues: [UInt8]
            do {
                combinedFiveBitValues = [UInt8](
                    try OpalCryptoAdapter.decodeBase32Values(encodedPayload)
                )
            } catch {
                throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
            }
            guard combinedFiveBitValues.count > Self.checksumSymbolCount else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
            }

            let checksumInput = Self.prefixExpansion(scheme)
                + [0]
                + combinedFiveBitValues
            guard (try? OpalCryptoAdapter.computePolymod(checksumInput)) == 0 else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidChecksum
            }

            let payloadFiveBitValues = Array(
                combinedFiveBitValues.dropLast(Self.checksumSymbolCount)
            )
            let payload: Data
            do {
                payload = Data(
                    try BitConversion.convertBits(
                        payloadFiveBitValues,
                        from: 5,
                        to: 8,
                        pad: false
                    )
                )
                let canonicalFiveBitValues = try BitConversion.convertBits(
                    [UInt8](payload),
                    from: 8,
                    to: 5,
                    pad: true
                )
                guard canonicalFiveBitValues == payloadFiveBitValues else {
                    throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
                }
            } catch let error as OpalBase.ReusablePaymentAddress.Error {
                throw error
            } catch {
                throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
            }

            guard payload.count == Self.payloadByteCount else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidPayloadLength(payload.count)
            }

            let version = payload[0]
            guard version == expectedVersion else {
                throw OpalBase.ReusablePaymentAddress.Error.unsupportedVersion(version)
            }

            let rawPrefixLength = payload[1]
            guard let prefixLength = OpalBase.ReusablePaymentAddress.PrefixLength(
                rawValue: rawPrefixLength
            ) else {
                throw OpalBase.ReusablePaymentAddress.Error.unsupportedPrefixLength(
                    rawPrefixLength
                )
            }
            if profile == .cashCodeV1, prefixLength != .sixteenBits {
                throw OpalBase.ReusablePaymentAddress.Error.unsupportedPrefixLength(
                    rawPrefixLength
                )
            }

            let scanPublicKey: OpalBase.Key.PublicKey
            let spendPublicKey: OpalBase.Key.PublicKey
            do {
                scanPublicKey = try OpalBase.Key.PublicKey(
                    compressedData: Data(payload[2..<35])
                )
                spendPublicKey = try OpalBase.Key.PublicKey(
                    compressedData: Data(payload[35..<68])
                )
            } catch {
                throw OpalBase.ReusablePaymentAddress.Error.invalidPublicKey
            }

            let expirationValue = payload[68..<72].reduce(UInt32.zero) {
                ($0 << 8) | UInt32($1)
            }
            let expiration: OpalBase.ReusablePaymentAddress.Expiration =
                expirationValue == 0 ? .never : .unixTime(expirationValue)
            if profile == .cashCodeV1, expiration != .never {
                throw OpalBase.ReusablePaymentAddress.Error.unsupportedExpiration
            }

            switch profile {
            case .cashCodeV1:
                return OpalBase.ReusablePaymentAddress(
                    cashCodeV1For: network,
                    scanPublicKey: scanPublicKey,
                    spendPublicKey: spendPublicKey
                )
            case .legacyElectronCash:
                return OpalBase.ReusablePaymentAddress(
                    legacyElectronCashFor: network,
                    prefixLength: prefixLength,
                    expiration: expiration,
                    scanPublicKey: scanPublicKey,
                    spendPublicKey: spendPublicKey
                )
            }
        }

        public func encode(_ reusablePaymentAddress: OpalBase.ReusablePaymentAddress) throws -> String {
            guard reusablePaymentAddress.profile == .cashCodeV1 else {
                throw OpalBase.ReusablePaymentAddress.Error.legacyProfileIsReadOnly
            }
            guard reusablePaymentAddress.prefixLength == .sixteenBits else {
                throw OpalBase.ReusablePaymentAddress.Error.unsupportedPrefixLength(
                    reusablePaymentAddress.prefixLength.rawValue
                )
            }
            guard reusablePaymentAddress.expiration == .never else {
                throw OpalBase.ReusablePaymentAddress.Error.unsupportedExpiration
            }

            let scheme: String
            let version: UInt8
            switch reusablePaymentAddress.network {
            case .mainnet:
                scheme = "cashcode"
                version = Self.mainnetVersion
            case .testnet, .chipnet:
                scheme = "cashcodetest"
                version = Self.testNetworkVersion
            }

            var payload = Data([
                version,
                reusablePaymentAddress.prefixLength.rawValue,
            ])
            payload.append(reusablePaymentAddress.scanPublicKey.compressedData)
            payload.append(reusablePaymentAddress.spendPublicKey.compressedData)
            payload.append(contentsOf: [0, 0, 0, 0])
            guard payload.count == Self.payloadByteCount else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidPayloadLength(payload.count)
            }

            let payloadFiveBitValues: [UInt8]
            do {
                payloadFiveBitValues = try BitConversion.convertBits(
                    [UInt8](payload),
                    from: 8,
                    to: 5,
                    pad: true
                )
            } catch {
                throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
            }

            let checksum = try Self.makeChecksum(
                scheme: scheme,
                payloadFiveBitValues: payloadFiveBitValues
            )
            let encodedPayload: String
            do {
                encodedPayload = try OpalCryptoAdapter.encodeBase32(
                    Data(payloadFiveBitValues + checksum),
                    interpretedAsFiveBitValues: true
                )
            } catch {
                throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
            }
            return "\(scheme):\(encodedPayload)"
        }

        private static func prefixExpansion(_ scheme: String) -> [UInt8] {
            scheme.utf8.map { $0 & 0x1f }
        }

        private static func makeChecksum(
            scheme: String,
            payloadFiveBitValues: [UInt8]
        ) throws -> [UInt8] {
            let checksumTemplate = [UInt8](
                repeating: 0,
                count: checksumSymbolCount
            )
            let polymod: UInt64
            do {
                polymod = try OpalCryptoAdapter.computePolymod(
                    prefixExpansion(scheme)
                    + [0]
                    + payloadFiveBitValues
                    + checksumTemplate
                )
            } catch {
                throw OpalBase.ReusablePaymentAddress.Error.invalidEncoding
            }

            return (0..<checksumSymbolCount).map { index in
                let shift = UInt64(5 * (checksumSymbolCount - 1 - index))
                return UInt8((polymod >> shift) & 0x1f)
            }
        }
    }
}
