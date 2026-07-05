// OpalBase+ReusablePaymentAddress+BackupMetadata.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct BackupMetadata: Sendable, Hashable {
        public let walletBirthday: WalletBirthday
        public let scanKeyDescriptor: ScanKeyDescriptor
        public let labelStates: [LabelState]

        public init(
            walletBirthday: WalletBirthday,
            scanKeyDescriptor: ScanKeyDescriptor,
            labelStates: [LabelState] = []
        ) {
            self.walletBirthday = walletBirthday
            self.scanKeyDescriptor = scanKeyDescriptor
            self.labelStates = labelStates
        }
    }
}
