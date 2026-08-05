// OpalBase+ReusablePaymentAddress+Profile.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public enum Profile: String, Codable, Sendable, Hashable {
        case cashCodeV1
        case legacyElectronCash
    }
}
