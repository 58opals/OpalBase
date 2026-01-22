// Network+MempoolFeeHistogramBin.swift

import Foundation

extension Network {
    public struct MempoolFeeHistogramBin: Sendable, Equatable {
        public let fee: Double
        public let virtualSize: UInt
        
        public init(fee: Double, virtualSize: UInt) {
            self.fee = fee
            self.virtualSize = virtualSize
        }
    }
}
