import Foundation
import Testing
@testable import OpalBase

@Suite("Account PrivacyShaper", .tags(.unit, .wallet))
struct AccountPrivacyShaperTests {
    @Test("organizeOutputs canonicalizes ordering when randomization is disabled")
    func testOrganizeOutputsCanonicalizesWhenRandomizationDisabled() async {
        let configuration = Account.PrivacyShaper.Configuration(shouldRandomizeRecipientOrdering: false)
        let shaper = Account.PrivacyShaper(configuration: configuration)
        
        let outputs = [
            Transaction.Output(value: 6_000, lockingScript: Data([0x02])),
            Transaction.Output(value: 1_000, lockingScript: Data([0x03])),
            Transaction.Output(value: 6_000, lockingScript: Data([0x01]))
        ]
        
        let organizedOutputs = await shaper.organizeOutputs(outputs)
        
        #expect(organizedOutputs != outputs)
        #expect(organizedOutputs.map(\.value) == [1_000, 6_000, 6_000])
        #expect(organizedOutputs[0].lockingScript == Data([0x03]))
        #expect(organizedOutputs[1].lockingScript == Data([0x01]))
        #expect(organizedOutputs[2].lockingScript == Data([0x02]))
    }
}
