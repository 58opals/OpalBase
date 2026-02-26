// NetworkModel+BlockHeaderSnapshotModel.swift

import Foundation

extension NetworkModel {
    public struct BlockHeaderSnapshotModel: Sendable, Equatable {
        public let height: UInt
        public let headerHexadecimal: String
        
        public init(height: UInt, headerHexadecimal: String) {
            self.height = height
            self.headerHexadecimal = headerHexadecimal
        }
    }
}
