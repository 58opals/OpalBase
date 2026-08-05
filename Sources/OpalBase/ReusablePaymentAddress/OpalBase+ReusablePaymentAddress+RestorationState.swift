// OpalBase+ReusablePaymentAddress+RestorationState.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// Durable public-only Cash Code restoration state.
    ///
    /// This value intentionally excludes signing capabilities, complete Cash
    /// Codes, filter prefixes, shared material, and raw transactions.
    public struct RestorationState: Codable, Hashable, Sendable {
        static let currentSchemaVersion: UInt32 = 1

        public let schemaVersion: UInt32
        public let revision: UInt64
        public let profile: Profile
        public let network: OpalBase.Network.Environment
        public let prefixLength: PrefixLength
        public let expirationUnixTime: UInt32?
        public let scanPublicKeyData: Data
        public let spendPublicKeyData: Data
        public let keyOrigin: KeyOrigin
        public let restoreStartHeight: UInt
        public let nextUnscannedHeight: UInt
        public let confirmedMatches: [ConfirmedMatch]
        public let mempoolMatches: [MempoolMatch]
        public let reorganizationHistory: [ReorganizationMetadata]

        public var lastReorganization: ReorganizationMetadata? {
            reorganizationHistory.last
        }

        init(
            revision: UInt64,
            address: OpalBase.ReusablePaymentAddress,
            keyOrigin: KeyOrigin,
            restoreStartHeight: UInt,
            nextUnscannedHeight: UInt,
            confirmedMatches: [ConfirmedMatch] = .init(),
            mempoolMatches: [MempoolMatch] = .init(),
            reorganizationHistory: [ReorganizationMetadata] = .init()
        ) {
            self.schemaVersion = Self.currentSchemaVersion
            self.revision = revision
            self.profile = address.profile
            self.network = address.network
            self.prefixLength = address.prefixLength
            self.expirationUnixTime = switch address.expiration {
            case .never: nil
            case .unixTime(let value): value
            }
            self.scanPublicKeyData = address.scanPublicKey.compressedData
            self.spendPublicKeyData = address.spendPublicKey.compressedData
            self.keyOrigin = keyOrigin
            self.restoreStartHeight = restoreStartHeight
            self.nextUnscannedHeight = nextUnscannedHeight
            self.confirmedMatches = confirmedMatches
            self.mempoolMatches = mempoolMatches
            self.reorganizationHistory = reorganizationHistory
        }

        func makeReplacement(
            revision: UInt64,
            nextUnscannedHeight: UInt? = nil,
            confirmedMatches: [ConfirmedMatch]? = nil,
            mempoolMatches: [MempoolMatch]? = nil,
            reorganizationHistory: [ReorganizationMetadata]? = nil
        ) throws -> Self {
            try Self(
                revision: revision,
                address: makeReusablePaymentAddress(),
                keyOrigin: keyOrigin,
                restoreStartHeight: restoreStartHeight,
                nextUnscannedHeight: nextUnscannedHeight ?? self.nextUnscannedHeight,
                confirmedMatches: confirmedMatches ?? self.confirmedMatches,
                mempoolMatches: mempoolMatches ?? self.mempoolMatches,
                reorganizationHistory:
                    reorganizationHistory ?? self.reorganizationHistory
            )
        }

        func makeReusablePaymentAddress() throws -> OpalBase.ReusablePaymentAddress {
            guard profile == .cashCodeV1,
                  prefixLength == .sixteenBits,
                  expirationUnixTime == nil
            else {
                throw Error.invalidPersistentState
            }
            return try OpalBase.ReusablePaymentAddress(
                cashCodeV1For: network,
                scanPublicKey: OpalBase.Key.PublicKey(compressedData: scanPublicKeyData),
                spendPublicKey: OpalBase.Key.PublicKey(compressedData: spendPublicKeyData)
            )
        }
    }
}
