// NetworkModel~AddressReadable.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public typealias AddressReadable = AddressQueryClient & AddressSubscriptionClient
    
    public enum TokenFilter: String, Sendable, Equatable {
        case include = "include_tokens"
        case exclude = "exclude_tokens"
        case only = "tokens_only"
    }
}

extension NetworkModel.TokenFilter {
    var fulcrumTokenFilter: SwiftFulcrum.RPC.Method.Blockchain.CashTokens.TokenFilter {
        switch self {
        case .include:
            return .include
        case .exclude:
            return .exclude
        case .only:
            return .only
        }
    }
}
