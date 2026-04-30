// OpalBase+Network+Fulcrum+MempoolReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public struct MempoolReader {
        private let client: any MempoolClient
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        
        public init(client: Client, timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()) {
            self.init(client: client as any MempoolClient, timeouts: timeouts)
        }

        init(client: any MempoolClient, timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchMempoolInfo() async throws -> OpalBase.Network.MempoolInfo {
            try await OpalBase.Network.performWithFailureTranslation {
                let response = try await client.fetchMempoolInfo(options: .init(timeout: timeouts.mempoolInfo))
                
                return OpalBase.Network.MempoolInfo(
                    mempoolMinimumFee: response.mempoolMinimumFee,
                    minimumRelayTransactionFee: response.minimumRelayTransactionFee,
                    incrementalRelayFee: response.incrementalRelayFee,
                    unbroadcastCount: response.unbroadcastCount,
                    isFullReplaceByFeeEnabled: response.isFullReplaceByFeeEnabled
                )
            }
        }
        
        public func fetchFeeHistogram() async throws -> [OpalBase.Network.MempoolFeeHistogramBin] {
            try await OpalBase.Network.performWithFailureTranslation {
                let response = try await client.fetchMempoolFeeHistogram(
                    options: .init(timeout: timeouts.mempoolFeeHistogram)
                )
                
                return response.histogram.map { result in
                    OpalBase.Network.MempoolFeeHistogramBin(fee: result.fee, virtualSize: result.virtualSize)
                }.sorted { lhs, rhs in
                    if lhs.fee == rhs.fee {
                        return lhs.virtualSize < rhs.virtualSize
                    }
                    return lhs.fee < rhs.fee
                }
            }
        }
    }
}
