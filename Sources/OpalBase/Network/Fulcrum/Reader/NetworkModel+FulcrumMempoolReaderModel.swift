// NetworkModel+FulcrumMempoolReaderModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public struct FulcrumMempoolReaderModel {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeoutModel
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeoutModel = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchMempoolInfo() async throws -> MempoolInfoModel {
            try await NetworkModel.performWithFailureTranslation {
                let response = try await client.request(
                    method: .mempool(.getInfo),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.MempoolModel.GetInfoModel.self,
                    options: .init(timeout: timeouts.mempoolInfo)
                )
                
                return MempoolInfoModel(
                    mempoolMinimumFee: response.mempoolMinimumFee,
                    minimumRelayTransactionFee: response.minimumRelayTransactionFee,
                    incrementalRelayFee: response.incrementalRelayFee,
                    unbroadcastCount: response.unbroadcastCount,
                    isFullReplaceByFeeEnabled: response.isFullReplaceByFeeEnabled
                )
            }
        }
        
        public func fetchFeeHistogram() async throws -> [MempoolFeeHistogramBinModel] {
            try await NetworkModel.performWithFailureTranslation {
                let response = try await client.request(
                    method: .mempool(.getFeeHistogram),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.MempoolModel.GetFeeHistogramModel.self,
                    options: .init(timeout: timeouts.mempoolFeeHistogram)
                )
                
                return response.histogram.map { result in
                    MempoolFeeHistogramBinModel(fee: result.fee, virtualSize: result.virtualSize)
                }
            }
        }
    }
}
