// OpalBase+Network+BlockHeaderSnapshot.swift

import Foundation

extension _OpalBase.Network {
    public struct BlockHeaderSnapshot: Sendable, Equatable {
        public let height: UInt
        public let headerHexadecimal: String
        
        public init(height: UInt, headerHexadecimal: String) {
            self.height = height
            self.headerHexadecimal = headerHexadecimal
        }
    }
}
