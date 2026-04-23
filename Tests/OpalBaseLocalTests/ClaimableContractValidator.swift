// ClaimableContractValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Claimable contract", .tags(.unit))
struct ClaimableContractValidator {
    @Test("redeem script is deterministic and funding script is standard P2SH")
    func redeemScriptIsDeterministicAndFundingScriptIsStandardP2SH() throws {
        let claimPublicKeyHash = Data(repeating: 0x11, count: 20)
        let refundPublicKeyHash = Data(repeating: 0x22, count: 20)
        let contract = try OpalBase.Claimable.Contract(
            network: .chipnet,
            claimPublicKeyHash: claimPublicKeyHash,
            refundPublicKeyHash: refundPublicKeyHash,
            expiryBlockHeight: 500
        )
        let sameContract = try OpalBase.Claimable.Contract(
            network: .chipnet,
            claimPublicKeyHash: claimPublicKeyHash,
            refundPublicKeyHash: refundPublicKeyHash,
            expiryBlockHeight: 500
        )
        let decodedFundingScript = try OpalBase.Script.decode(
            lockingScript: contract.fundingLockingScriptData
        )

        #expect(contract.redeemScriptData == sameContract.redeemScriptData)
        #expect(contract.fundingScriptHashData == sameContract.fundingScriptHashData)
        #expect(decodedFundingScript == .p2sh(scriptHash: contract.fundingScriptHashData))
    }

    @Test("draft derives claim branch and funding output")
    func draftDerivesClaimBranchAndFundingOutput() throws {
        let (draft, refundPrivateKey) = try makeClaimableDraft()
        let fundingOutput = draft.makeFundingOutput(value: 42_000)
        let expectedClaimPublicKeyHash = try makeClaimablePublicKeyHash(
            from: draft.claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )
        let expectedRefundPublicKeyHash = try makeClaimablePublicKeyHash(
            from: refundPrivateKey,
            invalidError: .invalidRefundPrivateKey
        )

        #expect(draft.contract.claimPublicKeyHash == expectedClaimPublicKeyHash)
        #expect(draft.contract.refundPublicKeyHash == expectedRefundPublicKeyHash)
        #expect(fundingOutput.value == 42_000)
        #expect(fundingOutput.lockingScript == draft.contract.fundingLockingScriptData)
    }
}
