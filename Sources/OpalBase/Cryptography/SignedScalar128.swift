// SignedScalar128.swift

import Foundation

struct SignedScalar128: Sendable, Equatable {
    let magnitude: UInt256
    let isNegative: Bool
    
    init(magnitude: UInt256, isNegative: Bool) {
        if let mostSignificantBitIndex = magnitude.mostSignificantBitIndex {
            precondition(mostSignificantBitIndex < 128, "SignedScalar128 magnitude exceeds 128 bits.")
        }
        self.magnitude = magnitude
        self.isNegative = isNegative && !magnitude.isZero
    }
    
    var isZero: Bool {
        magnitude.isZero
    }
}
