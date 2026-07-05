// OpalBase+ReusablePaymentAddress+WalletBirthday.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct WalletBirthday: Sendable, Hashable {
        public let blockHeight: Int
        public let date: Date?

        public init(blockHeight: Int, date: Date? = nil) throws {
            guard blockHeight >= 0 else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidBlockHeight(blockHeight)
            }
            self.blockHeight = blockHeight
            self.date = date
        }
    }
}
