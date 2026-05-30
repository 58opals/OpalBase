// OpalBase+Network+TokenFilter.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
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
