// SignedScalar128Model.swift

import Foundation

struct SignedScalar128Model: Sendable, Equatable {
    let magnitude: UInt256Model
    let isNegative: Bool
    
    init(magnitude: UInt256Model, isNegative: Bool) {
        if let mostSignificantBitIndex = magnitude.mostSignificantBitIndex {
            precondition(mostSignificantBitIndex < 128, "SignedScalar128Model magnitude exceeds 128 bits.")
        }
        self.magnitude = magnitude
        self.isNegative = isNegative && !magnitude.isZero
    }
    
    var isZero: Bool {
        magnitude.isZero
    }
}
