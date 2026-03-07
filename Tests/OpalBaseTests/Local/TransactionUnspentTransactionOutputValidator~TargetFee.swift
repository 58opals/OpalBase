// TransactionUnspentTransactionOutputValidator~TargetFee.swift

import Foundation
import Testing
@testable import OpalBase

extension TransactionUnspentTransactionOutputValidator {
    @Test("computeOutputsForTargetFee handles dust donation policy")
    func computeOutputsForTargetFeeHandlesDustDonationPolicy() throws {
        let recipientOutputs = [OpalBase.Transaction.OutputModel(value: 1_000, lockingScript: Data([0x51]))]
        let changeOutput = OpalBase.Transaction.OutputModel(value: 900, lockingScript: Data([0x52]))
        let targetFee = UInt64(850)
        
        let donationOutputs = try OpalBase.Transaction.computeOutputsForTargetFee(
            recipientOutputs: recipientOutputs,
            changeOutputTemplate: changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            targetFee: targetFee,
            shouldAllowDustDonation: true
        )
        
        #expect(donationOutputs.count == recipientOutputs.count)
        
        #expect(throws: OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit) {
            _ = try OpalBase.Transaction.computeOutputsForTargetFee(
                recipientOutputs: recipientOutputs,
                changeOutputTemplate: changeOutput,
                outputOrderingStrategy: .privacyRandomized,
                targetFee: targetFee,
                shouldAllowDustDonation: false
            )
        }
    }
    
    @Test("computeOutputsForTargetFee applies privacy output shuffler to change output")
    func computeOutputsForTargetFeeAppliesPrivacyOutputShuffler() throws {
        let recipientA = OpalBase.Transaction.OutputModel(value: 6_000, lockingScript: Data([0x51]))
        let recipientB = OpalBase.Transaction.OutputModel(value: 1_000, lockingScript: Data([0x52]))
        let changeOutput = OpalBase.Transaction.OutputModel(value: 3_000, lockingScript: Data([0x53]))
        
        let outputs = try OpalBase.Transaction.computeOutputsForTargetFee(
            recipientOutputs: [recipientA, recipientB],
            changeOutputTemplate: changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            targetFee: 0,
            shouldAllowDustDonation: false,
            privacyOutputShuffle: { values in Array(values.reversed()) }
        )
        
        #expect(outputs.map(\.value) == [3_000, 1_000, 6_000])
        #expect(outputs.first?.lockingScript == changeOutput.lockingScript)
    }
    
    @Test("computeOutputsForTargetFee preserves token metadata on change outputs")
    func computeOutputsForTargetFeePreservesTokenMetadataOnChangeOutputs() throws {
        let recipientOutput = OpalBase.Transaction.OutputModel(value: 1_000, lockingScript: Data([0x51]))
        let tokenData = try makeTokenData(fillByte: 0x5A, amount: 7)
        let changeOutput = OpalBase.Transaction.OutputModel(
            value: 3_000,
            lockingScript: Data([0x53]),
            tokenData: tokenData
        )
        
        let outputs = try OpalBase.Transaction.computeOutputsForTargetFee(
            recipientOutputs: [recipientOutput],
            changeOutputTemplate: changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            targetFee: 0,
            shouldAllowDustDonation: false,
            privacyOutputShuffle: { $0 }
        )
        
        let resolvedChangeOutput = try #require(outputs.first { output in
            output.lockingScript == changeOutput.lockingScript && output.value == changeOutput.value
        })
        #expect(resolvedChangeOutput.tokenData == tokenData)
    }
}
