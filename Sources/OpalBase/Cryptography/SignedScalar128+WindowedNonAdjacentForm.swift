// SignedScalar128+WindowedNonAdjacentForm.swift

import Foundation

extension SignedScalar128 {
    static func makeWindowedNonAdjacentForm(_ scalar: SignedScalar128, width: Int) -> [Int8] {
        precondition(width >= 2 && width <= 8, "Unsupported window width for windowed non-adjacent form.")
        guard !scalar.isZero else {
            return [0]
        }
        
        let windowMask = UInt64((1 << width) - 1)
        let windowHalf = Int64(1 << (width - 1))
        let windowFull = Int64(1 << width)
        
        var magnitude = scalar.magnitude
        var digits: [Int8] = .init()
        digits.reserveCapacity(130)
        
        while !magnitude.isZero {
            var digit: Int64 = 0
            if (magnitude.limbs[0] & 1) == 1 {
                let lowBits = Int64(magnitude.limbs[0] & windowMask)
                digit = lowBits
                if digit > windowHalf {
                    digit -= windowFull
                }
                if digit < 0 {
                    magnitude = magnitude.addWord(UInt64(-digit))
                } else {
                    magnitude = magnitude.subtractWord(UInt64(digit))
                }
            }
            
            digits.append(scalar.isNegative ? Int8(-digit) : Int8(digit))
            magnitude = magnitude.shiftRightOneBit()
        }
        
        return digits
    }
}
