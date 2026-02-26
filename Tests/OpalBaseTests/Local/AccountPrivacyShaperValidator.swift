import Foundation
import Testing
@testable import OpalBase

@Suite("AccountActor PrivacyShaperActor", .tags(.unit, .wallet))
struct AccountPrivacyShaperValidator {
    @Test("organizeOutputs canonicalizes ordering when randomization is disabled")
    func organizeOutputsCanonicalizesWhenRandomizationDisabled() async {
        let configuration = AccountActor.PrivacyShaperActor.Configuration(shouldRandomizeRecipientOrdering: false)
        let shaper = AccountActor.PrivacyShaperActor(configuration: configuration)
        
        let outputs = [
            TransactionModel.OutputModel(value: 6_000, lockingScript: Data([0x02])),
            TransactionModel.OutputModel(value: 1_000, lockingScript: Data([0x03])),
            TransactionModel.OutputModel(value: 6_000, lockingScript: Data([0x01]))
        ]
        
        let organizedOutputs = await shaper.organizeOutputs(outputs)
        
        #expect(organizedOutputs != outputs)
        #expect(organizedOutputs.map(\.value) == [1_000, 6_000, 6_000])
        #expect(organizedOutputs[0].lockingScript == Data([0x03]))
        #expect(organizedOutputs[1].lockingScript == Data([0x01]))
        #expect(organizedOutputs[2].lockingScript == Data([0x02]))
    }
}
