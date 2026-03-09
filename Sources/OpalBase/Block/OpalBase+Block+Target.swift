// OpalBase+Block+Target.swift

import Foundation

extension _OpalBase.Block {
    public struct Target: Comparable, Sendable {
        let value: LargeUnsignedInteger

        public init(data: Data) {
            self.value = LargeUnsignedInteger(data)
        }

        init(_ value: LargeUnsignedInteger) {
            self.value = value
        }

        public static func < (lhs: OpalBase.Block.Target, rhs: OpalBase.Block.Target) -> Bool {
            lhs.value < rhs.value
        }
    }
}
