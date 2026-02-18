// Network+FulcrumMempoolReader.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumMempoolReader {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeout
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchMempoolInfo() async throws -> MempoolInfo {
            try await Network.performWithFailureTranslation {
                let response = try await client.request(
                    method: .mempool(.getInfo),
                    responseType: Response.ResultModel.MempoolModel.GetInfoModel.self,
                    options: .init(timeout: timeouts.mempoolInfo)
                )
                
                return MempoolInfo(
                    mempoolMinimumFee: response.mempoolMinimumFee,
                    minimumRelayTransactionFee: response.minimumRelayTransactionFee,
                    incrementalRelayFee: response.incrementalRelayFee,
                    unbroadcastCount: response.unbroadcastCount,
                    isFullReplaceByFeeEnabled: response.isFullReplaceByFeeEnabled
                )
            }
        }
        
        public func fetchFeeHistogram() async throws -> [MempoolFeeHistogramBin] {
            try await Network.performWithFailureTranslation {
                let response = try await client.request(
                    method: .mempool(.getFeeHistogram),
                    responseType: Response.ResultModel.MempoolModel.GetFeeHistogramModel.self,
                    options: .init(timeout: timeouts.mempoolFeeHistogram)
                )
                
                return response.histogram.map { result in
                    MempoolFeeHistogramBin(fee: result.fee, virtualSize: result.virtualSize)
                }
            }
        }
    }
}
