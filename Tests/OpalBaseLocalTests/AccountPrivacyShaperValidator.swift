// AccountPrivacyShaperValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account PrivacyShaperActor", .tags(.unit, .wallet))
struct AccountPrivacyShaperValidator {
    @Test("organizeOutputs canonicalizes ordering when randomization is disabled")
    func organizeOutputsCanonicalizesWhenRandomizationDisabled() async throws {
        let configuration = OpalBase.Account.PrivacyShaperActor.Configuration(shouldRandomizeRecipientOrdering: false)
        let shaper = OpalBase.Account.PrivacyShaperActor(configuration: configuration)
        
        let outputs = [
            OpalBase.Transaction.Output(value: 6_000, lockingScript: Data([0x02])),
            OpalBase.Transaction.Output(value: 1_000, lockingScript: Data([0x03])),
            OpalBase.Transaction.Output(value: 6_000, lockingScript: Data([0x01]))
        ]
        
        let organizedOutputs = try await shaper.organizeOutputs(outputs)
        
        #expect(organizedOutputs != outputs)
        try #require(organizedOutputs.count == outputs.count)
        #expect(organizedOutputs.map(\.value) == [1_000, 6_000, 6_000])
        #expect(organizedOutputs[0].lockingScript == Data([0x03]))
        #expect(organizedOutputs[1].lockingScript == Data([0x01]))
        #expect(organizedOutputs[2].lockingScript == Data([0x02]))
    }

    @Test("nextDecoyCount clamps negative decoy ranges")
    func nextDecoyCountClampsNegativeDecoyRanges() async {
        let configuration = OpalBase.Account.PrivacyShaperActor.Configuration(
            decoyQueryRange: -3 ... -1,
            decoyProbability: 1
        )
        let shaper = OpalBase.Account.PrivacyShaperActor(configuration: configuration)

        #expect(await shaper.nextDecoyCount == 0)
    }

    @Test("nextDecoyCount clamps mixed negative decoy ranges")
    func nextDecoyCountClampsMixedNegativeDecoyRanges() async {
        let configuration = OpalBase.Account.PrivacyShaperActor.Configuration(
            decoyQueryRange: -3 ... 2,
            decoyProbability: 1
        )
        let shaper = OpalBase.Account.PrivacyShaperActor(configuration: configuration)

        for _ in 0..<20 {
            #expect((0...2).contains(await shaper.nextDecoyCount))
        }
    }

    @Test(
        "configuration clamps invalid decoy probabilities",
        arguments: [
            (-Double.infinity, 0),
            (Double.infinity, 1),
            (Double.nan, 0)
        ]
    )
    func configurationClampsInvalidDecoyProbabilities(
        decoyProbability: Double,
        expectedDecoyProbability: Double
    ) {
        let configuration = OpalBase.Account.PrivacyShaperActor.Configuration(
            decoyProbability: decoyProbability
        )

        #expect(configuration.decoyProbability == expectedDecoyProbability)
    }

}
