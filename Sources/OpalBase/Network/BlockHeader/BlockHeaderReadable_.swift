// Network+BlockHeaderReadable_.swift

import Foundation

extension Network {
    public typealias BlockHeaderReadable = BlockHeaderQuerying & BlockHeaderSubscribing
    
    public protocol BlockHeaderQuerying: Sendable {
        func fetchTip() async throws -> BlockHeaderSnapshot
    }
    
    public protocol BlockHeaderSubscribing: Sendable {
        func subscribeToTip() async throws -> AsyncThrowingStream<BlockHeaderSnapshot, Network.Failure>
    }
}
