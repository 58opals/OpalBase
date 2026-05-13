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
                let response: SwiftFulcrum.Response.Mempool.GetInfo
                do {
                    response = try await client.fetchMempoolInfo(options: .init(timeout: timeouts.mempoolInfo))
                } catch {
                    if let normalizedError = Self.normalizedMempoolInfoDecodeError(from: error) {
                        throw normalizedError
                    }
                    throw error
                }
                
                return OpalBase.Network.MempoolInfo(
                    mempoolMinimumFee: try Self.validateMempoolInfoFeeRate(
                        response.mempoolMinimumFee,
                        fieldName: "mempool minimum fee"
                    ),
                    minimumRelayTransactionFee: try Self.validateMempoolInfoFeeRate(
                        response.minimumRelayTransactionFee,
                        fieldName: "minimum relay transaction fee"
                    ),
                    incrementalRelayFee: try Self.validateMempoolInfoFeeRate(
                        response.incrementalRelayFee,
                        fieldName: "incremental relay fee"
                    ),
                    unbroadcastCount: try Self.validateMempoolInfoCount(
                        response.unbroadcastCount,
                        fieldName: "unbroadcast count"
                    ),
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

        private static func normalizedMempoolInfoDecodeError(
            from error: Swift.Error
        ) -> OpalBase.Network.Error? {
            guard let fulcrumError = error as? SwiftFulcrum.Client.Error,
                  case .coding(.decode(let underlying?)) = fulcrumError else {
                return nil
            }

            let description = String(describing: underlying)
            let fieldNames = [
                ("mempoolminfee", "mempool minimum fee"),
                ("minrelaytxfee", "minimum relay transaction fee"),
                ("incrementalrelayfee", "incremental relay fee"),
                ("unbroadcastcount", "unbroadcast count")
            ]

            for (wireField, displayField) in fieldNames {
                guard let value = invalidMempoolInfoValue(
                    in: description,
                    wireField: wireField
                ) else { continue }

                return OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid \(displayField): \(value)"
                )
            }

            return nil
        }

        private static func invalidMempoolInfoValue(
            in description: String,
            wireField: String
        ) -> String? {
            let marker = "Invalid \(wireField): "
            guard let markerRange = description.range(of: marker) else { return nil }

            var value = String(description[markerRange.upperBound...])
            if value.hasSuffix("\")") {
                value.removeLast(2)
            } else if value.hasSuffix("\"") {
                value.removeLast()
            }
            return value
        }
        
        private static func validateMempoolInfoFeeRate(_ feeRate: Double?, fieldName: String) throws -> Double? {
            guard let feeRate else { return nil }
            guard feeRate.isFinite, feeRate >= 0 else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid \(fieldName): \(feeRate)"
                )
            }
            return feeRate
        }
        
        private static func validateMempoolInfoCount(_ count: Int?, fieldName: String) throws -> Int? {
            guard let count else { return nil }
            guard count >= 0 else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid \(fieldName): \(count)"
                )
            }
            return count
        }
    }
}
