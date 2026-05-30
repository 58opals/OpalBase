// OpalBase+Network+BlockHeaderQueryClient.swift

import Foundation

extension _OpalBase.Network {
    protocol BlockHeaderQueryClient: Sendable {
        func fetchTip() async throws -> OpalBase.Network.BlockHeaderSnapshot
    }
}
