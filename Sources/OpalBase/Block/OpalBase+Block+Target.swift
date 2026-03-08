// OpalBase+Block+Target.swift

import Foundation

extension _OpalBase.Block {
    public struct Target: Comparable, Sendable {
        let value: LargeUnsignedIntegerModel

        public init(data: Data) {
            self.value = LargeUnsignedIntegerModel(data)
        }

        init(_ value: LargeUnsignedIntegerModel) {
            self.value = value
        }

        public static func < (lhs: OpalBase.Block.Target, rhs: OpalBase.Block.Target) -> Bool {
            lhs.value < rhs.value
        }
    }
}
