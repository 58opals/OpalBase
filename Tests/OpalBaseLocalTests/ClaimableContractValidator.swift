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

    @Test("normalizes sliced public key hashes")
    func normalizesSlicedPublicKeyHashes() throws {
        let claimPublicKeyHash = makeSlicedData(from: Data(repeating: 0x11, count: 20))
        let refundPublicKeyHash = makeSlicedData(from: Data(repeating: 0x22, count: 20))

        let contract = try OpalBase.Claimable.Contract(
            network: .chipnet,
            claimPublicKeyHash: claimPublicKeyHash,
            refundPublicKeyHash: refundPublicKeyHash,
            expiryBlockHeight: 500
        )

        #expect(claimPublicKeyHash.startIndex != 0)
        #expect(refundPublicKeyHash.startIndex != 0)
        #expect(contract.claimPublicKeyHash == Data(claimPublicKeyHash))
        #expect(contract.refundPublicKeyHash == Data(refundPublicKeyHash))
        #expect(contract.claimPublicKeyHash.startIndex == 0)
        #expect(contract.refundPublicKeyHash.startIndex == 0)
    }

    @Test("rejects timestamp locktime expiry")
    func rejectsTimestampLocktimeExpiry() throws {
        #expect(throws: OpalBase.Claimable.Error.invalidExpiryBlockHeight) {
            try OpalBase.Claimable.Contract(
                network: .chipnet,
                claimPublicKeyHash: Data(repeating: 0x11, count: 20),
                refundPublicKeyHash: Data(repeating: 0x22, count: 20),
                expiryBlockHeight: 500_000_000
            )
        }
    }

    @Test("rejects invalid public key hash lengths", arguments: InvalidPublicKeyHashCase.allCases)
    func rejectsInvalidPublicKeyHashLengths(_ invalidPublicKeyHashCase: InvalidPublicKeyHashCase) throws {
        #expect(throws: invalidPublicKeyHashCase.expectedError) {
            try OpalBase.Claimable.Contract(
                network: .chipnet,
                claimPublicKeyHash: invalidPublicKeyHashCase.claimPublicKeyHash,
                refundPublicKeyHash: invalidPublicKeyHashCase.refundPublicKeyHash,
                expiryBlockHeight: 500
            )
        }
    }

    @Test("draft derives claim branch and funding output")
    func draftDerivesClaimBranchAndFundingOutput() throws {
        let (draft, refundPrivateKey) = try ClaimableTestSupport.makeClaimableDraft()
        let fundingOutput = draft.makeFundingOutput(value: 42_000)
        let expectedClaimPublicKeyHash = try ClaimablePrimitiveOperation.makePublicKeyHash(
            from: draft.claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )
        let expectedRefundPublicKeyHash = try ClaimablePrimitiveOperation.makePublicKeyHash(
            from: refundPrivateKey,
            invalidError: .invalidRefundPrivateKey
        )

        #expect(draft.contract.claimPublicKeyHash == expectedClaimPublicKeyHash)
        #expect(draft.contract.refundPublicKeyHash == expectedRefundPublicKeyHash)
        #expect(fundingOutput.value == 42_000)
        #expect(fundingOutput.lockingScript == draft.contract.fundingLockingScriptData)
    }

    private func makeSlicedData(from data: Data) -> Data {
        var paddedData = Data([0x00])
        paddedData.append(data)
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }

    enum InvalidPublicKeyHashCase: CaseIterable, Sendable {
        case claim
        case refund

        var claimPublicKeyHash: Data {
            switch self {
            case .claim:
                return Data(repeating: 0x11, count: 19)
            case .refund:
                return Data(repeating: 0x11, count: 20)
            }
        }

        var refundPublicKeyHash: Data {
            switch self {
            case .claim:
                return Data(repeating: 0x22, count: 20)
            case .refund:
                return Data(repeating: 0x22, count: 21)
            }
        }

        var expectedError: OpalBase.Claimable.Error {
            switch self {
            case .claim:
                return .invalidClaimPublicKeyHash
            case .refund:
                return .invalidRefundPublicKeyHash
            }
        }
    }
}
