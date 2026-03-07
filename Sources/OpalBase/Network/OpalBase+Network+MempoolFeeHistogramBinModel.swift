// OpalBase+Network+MempoolFeeHistogramBinModel.swift

import Foundation

extension _OpalBase.Network {
    public struct MempoolFeeHistogramBinModel: Sendable, Equatable {
        public let fee: Double
        public let virtualSize: UInt
        
        public init(fee: Double, virtualSize: UInt) {
            self.fee = fee
            self.virtualSize = virtualSize
        }
    }
}
