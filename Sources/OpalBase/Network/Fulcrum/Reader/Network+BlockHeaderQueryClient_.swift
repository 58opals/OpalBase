// Network+BlockHeaderQueryClient_.swift

import Foundation

extension Network {
    public protocol BlockHeaderQueryClient: Sendable {
        func fetchTip() async throws -> BlockHeaderSnapshot
    }
}
