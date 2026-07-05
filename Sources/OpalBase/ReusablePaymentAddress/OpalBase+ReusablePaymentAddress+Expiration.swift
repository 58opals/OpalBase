// OpalBase+ReusablePaymentAddress+Expiration.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct Expiration: Sendable, Hashable {
        public static let never = Self(blockHeight: nil)

        public let blockHeight: Int?

        public init(blockHeight: Int) throws {
            guard blockHeight >= 0 else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidBlockHeight(blockHeight)
            }
            self.blockHeight = blockHeight
        }

        private init(blockHeight: Int?) {
            self.blockHeight = blockHeight
        }

        public var isFinite: Bool {
            blockHeight != nil
        }

        public func hasExpired(atBlockHeight currentBlockHeight: Int) -> Bool {
            guard let blockHeight else { return false }
            return currentBlockHeight >= blockHeight
        }
    }
}
