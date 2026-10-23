// OpalBase+Account+PrivacyShaperActor+Configuration.swift

import Foundation

extension _OpalBase.Account.PrivacyShaperActor {
    struct Configuration: Hashable, Sendable {
        let shouldRandomizeUTXOOrdering: Bool
        let shouldRandomizeRecipientOrdering: Bool

        init(shouldRandomizeUTXOOrdering: Bool = true,
             shouldRandomizeRecipientOrdering: Bool = true) {
            self.shouldRandomizeUTXOOrdering = shouldRandomizeUTXOOrdering
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }

        static let standard = Configuration()
    }
}
