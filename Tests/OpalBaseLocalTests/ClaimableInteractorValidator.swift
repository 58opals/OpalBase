// ClaimableInteractorValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Claimable interactor composition", .tags(.unit, .wallet))
struct ClaimableInteractorValidator {
    @Test("claimable interactor keeps claimable authoring domain-specific")
    func composeClaimableAuthoringAndSpends() throws {
        let interactor = OpalBase.ClaimableInteractor()
        let refundPrivateKey = ClaimableTestSupport.makeClaimablePrivateKey(lastByte: 0x02)
        let refundSigningKey = try OpalBase.Key.SigningKey(rawRepresentation: refundPrivateKey)
        let draft = try interactor.makeDraft(
            network: .chipnet,
            refundSigningKey: refundSigningKey,
            expiryBlockHeight: 720
        )
        let fundingOutput = interactor.makeFundingOutput(from: draft, value: 25_000)
        let envelope = try interactor.makeEnvelope(
            contract: draft.contract,
            claimPrivateKey: draft.claimPrivateKey,
            fundingTransactionHash: AccountTestFixtures.makeHash(byte: 0x41),
            fundingOutputIndex: 0,
            fundingValue: fundingOutput.value
        )
        let shareCode = try interactor.encodeShareCode(for: envelope)
        let decodedEnvelope = try interactor.decodeShareCode(shareCode)
        let status = interactor.makeLocalStatus(for: decodedEnvelope, currentBlockHeight: 700)
        let claimTransaction = try interactor.buildClaimTransaction(
            from: decodedEnvelope,
            destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(),
            currentBlockHeight: 700
        )
        let refundTransaction = try interactor.buildRefundTransaction(
            from: decodedEnvelope,
            refundSigningKey: refundSigningKey,
            destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x34),
            currentBlockHeight: 720
        )

        #expect(fundingOutput.lockingScript == draft.contract.fundingLockingScriptData)
        #expect(decodedEnvelope.contract == envelope.contract)
        #expect(status.allowsClaim)
        #expect(claimTransaction.inputs.count == 1)
        #expect(claimTransaction.outputs.count == 1)
        #expect(refundTransaction.inputs.count == 1)
        #expect(refundTransaction.outputs.count == 1)
    }
}
