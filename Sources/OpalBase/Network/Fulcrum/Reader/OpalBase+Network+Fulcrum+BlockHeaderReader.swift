// OpalBase+Network+Fulcrum+BlockHeaderReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public struct BlockHeaderReader: OpalBase.Network.BlockHeaderQueryClient, OpalBase.Network.BlockHeaderSubscriptionClient {
        private let client: Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        
        public init(client: Client, timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchTip() async throws -> OpalBase.Network.BlockHeaderSnapshot {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    SwiftFulcrum.API.blockchain.headers.tip,
                    options: .init(timeout: timeouts.headersTip)
                )
                return try Self.makeSnapshot(height: result.height, headerHexadecimal: result.hex)
            }
        }
        
        public func subscribeToTip() async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error> {
            try await OpalBase.Network.performWithFailureTranslation {
                let (initial, updates, cancel) = try await client.subscribe(
                    SwiftFulcrum.API.blockchain.headers.subscribe,
                    options: .init(timeout: timeouts.headersSubscription)
                )
                
                return OpalBase.Network.makeSubscriptionStream(
                    initial: initial,
                    updates: updates,
                    cancel: cancel,
                    makeInitialUpdates: { snapshot in
                        [
                            try Self.makeSnapshot(
                                height: snapshot.height,
                                headerHexadecimal: snapshot.hex
                            )
                        ]
                    },
                    makeUpdates: { notification in
                        try notification.blocks.map { block in
                            try Self.makeSnapshot(
                                height: block.height,
                                headerHexadecimal: block.hex
                            )
                        }
                    },
                    deduplicationKey: { snapshot in
                        snapshot
                    }
                )
            }
        }
        
        static func makeSnapshot(height: UInt, headerHexadecimal: String) throws -> OpalBase.Network.BlockHeaderSnapshot {
            func makeDecodeError() -> OpalBase.Network.Error {
                OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Cannot decode block header: \(headerHexadecimal)"
                )
            }

            guard !headerHexadecimal.hasPrefix("0x"), !headerHexadecimal.hasPrefix("0X") else {
                throw makeDecodeError()
            }

            let headerData: Data
            do {
                headerData = try Data(hexadecimalString: headerHexadecimal)
            } catch {
                throw makeDecodeError()
            }
            
            guard headerData.count == 80 else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid block header length: expected 80 bytes, got \(headerData.count)"
                )
            }
            
            return OpalBase.Network.BlockHeaderSnapshot(height: height, headerHexadecimal: headerHexadecimal)
        }
    }
}
