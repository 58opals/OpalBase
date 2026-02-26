// NetworkModel+BlockHeaderQueryClient_.swift

import Foundation

extension NetworkModel {
    public protocol BlockHeaderQueryClient: Sendable {
        func fetchTip() async throws -> BlockHeaderSnapshotModel
    }
}
