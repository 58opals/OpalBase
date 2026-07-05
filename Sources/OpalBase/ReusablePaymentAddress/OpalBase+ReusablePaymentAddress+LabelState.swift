// OpalBase+ReusablePaymentAddress+LabelState.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct LabelState: Sendable, Hashable {
        public let label: String
        public let nextIndex: UInt32

        public init(label: String, nextIndex: UInt32) throws {
            let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLabel.isEmpty else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidLabel(label)
            }
            self.label = trimmedLabel
            self.nextIndex = nextIndex
        }
    }
}
