// OpalBase+Network+Fulcrum+MempoolReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public struct MempoolReader {
        private let client: Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeoutModel
        
        public init(client: Client, timeouts: OpalBase.Network.FulcrumRequestTimeoutModel = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchMempoolInfo() async throws -> OpalBase.Network.MempoolInfoModel {
            try await OpalBase.Network.performWithFailureTranslation {
                let response = try await client.request(
                    method: .mempool(.getInfo),
                    responseType: SwiftFulcrum.RPC.Response.Result.Mempool.GetInfo.self,
                    options: .init(timeout: timeouts.mempoolInfo)
                )
                
                return OpalBase.Network.MempoolInfoModel(
                    mempoolMinimumFee: response.mempoolMinimumFee,
                    minimumRelayTransactionFee: response.minimumRelayTransactionFee,
                    incrementalRelayFee: response.incrementalRelayFee,
                    unbroadcastCount: response.unbroadcastCount,
                    isFullReplaceByFeeEnabled: response.isFullReplaceByFeeEnabled
                )
            }
        }
        
        public func fetchFeeHistogram() async throws -> [OpalBase.Network.MempoolFeeHistogramBinModel] {
            try await OpalBase.Network.performWithFailureTranslation {
                let response = try await client.request(
                    method: .mempool(.getFeeHistogram),
                    responseType: SwiftFulcrum.RPC.Response.Result.Mempool.GetFeeHistogram.self,
                    options: .init(timeout: timeouts.mempoolFeeHistogram)
                )
                
                return response.histogram.map { result in
                    OpalBase.Network.MempoolFeeHistogramBinModel(fee: result.fee, virtualSize: result.virtualSize)
                }
            }
        }
    }
}
