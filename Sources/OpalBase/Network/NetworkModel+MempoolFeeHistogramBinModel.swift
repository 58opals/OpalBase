// NetworkModel+MempoolFeeHistogramBinModel.swift

import Foundation

extension NetworkModel {
    public struct MempoolFeeHistogramBinModel: Sendable, Equatable {
        public let fee: Double
        public let virtualSize: UInt
        
        public init(fee: Double, virtualSize: UInt) {
            self.fee = fee
            self.virtualSize = virtualSize
        }
    }
}
