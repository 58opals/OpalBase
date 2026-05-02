// OpalBase+Network~AddressReadable.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
    typealias AddressReadable = AddressQueryClient & AddressSubscriptionClient
    
    public enum TokenFilter: String, Sendable, Equatable {
        case include = "include_tokens"
        case exclude = "exclude_tokens"
        case only = "tokens_only"
    }
}

extension _OpalBase.Network.TokenFilter {
    var fulcrumTokenFilter: SwiftFulcrum.CashTokens.TokenFilter {
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
