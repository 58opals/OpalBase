// OpalBase+Claimable+LocalStatus.swift

extension _OpalBase.Claimable {
    public struct LocalStatus {
        public let currentBlockHeight: UInt32
        public let expiryBlockHeight: UInt32

        public init(currentBlockHeight: UInt32, expiryBlockHeight: UInt32) {
            self.currentBlockHeight = currentBlockHeight
            self.expiryBlockHeight = expiryBlockHeight
        }

        public var isExpired: Bool {
            currentBlockHeight >= expiryBlockHeight
        }

        public var allowsClaim: Bool {
            currentBlockHeight < expiryBlockHeight
        }

        public var allowsRefund: Bool {
            isExpired
        }
    }
}

extension _OpalBase.Claimable.LocalStatus: Sendable {}
extension _OpalBase.Claimable.LocalStatus: Hashable {}
