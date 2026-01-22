// ScalarReduction.swift

import Foundation

enum ScalarReduction {
    @usableFromInline
    static let reductionConstant = UInt256(
        limbs: [
            0x402da1732fc9bebf,
            0x4551231950b75fc4,
            0x0000000000000001,
            0x0000000000000000
        ]
    )
    
    @inlinable
    static func reduce(_ value: UInt512) -> UInt256 {
        var foldedValue = value
        while true {
            let highPart = UInt256(limbs: [
                foldedValue.limbs[4],
                foldedValue.limbs[5],
                foldedValue.limbs[6],
                foldedValue.limbs[7]
            ])
            if highPart.isZero {
                var result = UInt256(limbs: [
                    foldedValue.limbs[0],
                    foldedValue.limbs[1],
                    foldedValue.limbs[2],
                    foldedValue.limbs[3]
                ])
                if result.compare(to: Secp256k1.Constant.n) != .orderedAscending {
                    result = result.subtract(Secp256k1.Constant.n).difference
                }
                return result
            }
            
            let lowPart = UInt256(limbs: [
                foldedValue.limbs[0],
                foldedValue.limbs[1],
                foldedValue.limbs[2],
                foldedValue.limbs[3]
            ])
            
            foldedValue = highPart.multiplyFullWidth(by: reductionConstant)
            addLow256(&foldedValue, lowPart)
        }
    }
    
    @inlinable
    static func addLow256(_ value: inout UInt512, _ lowPart: UInt256) {
        let currentLow = UInt256(limbs: [
            value.limbs[0],
            value.limbs[1],
            value.limbs[2],
            value.limbs[3]
        ])
        let addition = currentLow.add(lowPart)
        
        value.limbs[0] = addition.sum.limbs[0]
        value.limbs[1] = addition.sum.limbs[1]
        value.limbs[2] = addition.sum.limbs[2]
        value.limbs[3] = addition.sum.limbs[3]
        
        var carryValue: UInt64 = addition.carry ? 1 : 0
        var index = 4
        while carryValue != 0 && index < 8 {
            let (sum, overflow) = value.limbs[index].addingReportingOverflow(carryValue)
            value.limbs[index] = sum
            carryValue = overflow ? 1 : 0
            index += 1
        }
    }
}
