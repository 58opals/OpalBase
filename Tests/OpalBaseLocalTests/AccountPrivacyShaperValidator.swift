// AccountPrivacyShaperValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account PrivacyShaperActor", .tags(.unit, .wallet))
struct AccountPrivacyShaperValidator {
    @Test("organizeOutputs canonicalizes ordering when randomization is disabled")
    func organizeOutputsCanonicalizesWhenRandomizationDisabled() async {
        let configuration = OpalBase.Account.PrivacyShaperActor.Configuration(shouldRandomizeRecipientOrdering: false)
        let shaper = OpalBase.Account.PrivacyShaperActor(configuration: configuration)
        
        let outputs = [
            OpalBase.Transaction.Output(value: 6_000, lockingScript: Data([0x02])),
            OpalBase.Transaction.Output(value: 1_000, lockingScript: Data([0x03])),
            OpalBase.Transaction.Output(value: 6_000, lockingScript: Data([0x01]))
        ]
        
        let organizedOutputs = await shaper.organizeOutputs(outputs)
        
        #expect(organizedOutputs != outputs)
        #expect(organizedOutputs.map(\.value) == [1_000, 6_000, 6_000])
        #expect(organizedOutputs[0].lockingScript == Data([0x03]))
        #expect(organizedOutputs[1].lockingScript == Data([0x01]))
        #expect(organizedOutputs[2].lockingScript == Data([0x02]))
    }
}

