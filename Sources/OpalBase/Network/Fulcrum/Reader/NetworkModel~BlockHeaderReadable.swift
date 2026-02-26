// NetworkModel+BlockHeaderReadable.swift

import Foundation

extension NetworkModel {
    public typealias BlockHeaderReadable = BlockHeaderQueryClient & BlockHeaderSubscriptionClient
}
