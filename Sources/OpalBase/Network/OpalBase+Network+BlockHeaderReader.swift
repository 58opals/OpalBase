// OpalBase+Network+BlockHeaderReader.swift

import Foundation

extension _OpalBase.Network {
    public struct BlockHeaderReader: Sendable {
        private let fetchTipHandler: @Sendable () async throws -> OpalBase.Network.BlockHeaderSnapshot
        private let subscribeToTipHandler: @Sendable () async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error>

        public init(
            fetchTip: @escaping @Sendable () async throws -> OpalBase.Network.BlockHeaderSnapshot,
            subscribeToTip: @escaping @Sendable () async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error>
        ) {
            self.fetchTipHandler = fetchTip
            self.subscribeToTipHandler = subscribeToTip
        }

        public init(_ reader: OpalBase.Network.Fulcrum.BlockHeaderReader) {
            self.init(
                fetchTip: reader.fetchTip,
                subscribeToTip: reader.subscribeToTip
            )
        }

        init(_ reader: any OpalBase.Network.BlockHeaderReadable) {
            self.init(
                fetchTip: reader.fetchTip,
                subscribeToTip: reader.subscribeToTip
            )
        }

        public func fetchTip() async throws -> OpalBase.Network.BlockHeaderSnapshot {
            try await fetchTipHandler()
        }

        public func subscribeToTip() async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error> {
            try await subscribeToTipHandler()
        }
    }
}

extension _OpalBase.Network.BlockHeaderReader: OpalBase.Network.BlockHeaderQueryClient {}
extension _OpalBase.Network.BlockHeaderReader: OpalBase.Network.BlockHeaderSubscriptionClient {}
