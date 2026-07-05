// ReusablePaymentAddressBackupMetadataValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Reusable payment address backup metadata", .tags(.unit))
struct ReusablePaymentAddressBackupMetadataValidator {
    @Test("backup metadata carries wallet birthday, scan key descriptor, and label state")
    func preserveBackupMetadataFields() throws {
        let birthdayDate = Date(timeIntervalSince1970: 1_700_000_000)
        let birthday = try OpalBase.ReusablePaymentAddress.WalletBirthday(
            blockHeight: 800_000,
            date: birthdayDate
        )
        let derivationPath = try OpalBase.Key.DerivationPath(
            account: .init(rawIndexInteger: 0),
            usage: .receiving,
            index: 0
        )
        let descriptor = try OpalBase.ReusablePaymentAddress.ScanKeyDescriptor(
            scanPublicKey: ReusablePaymentAddressFixtureData.makePublicKey(),
            derivationPath: derivationPath
        )
        let labelState = try OpalBase.ReusablePaymentAddress.LabelState(
            label: " Savings ",
            nextIndex: 3
        )
        let metadata = OpalBase.ReusablePaymentAddress.BackupMetadata(
            walletBirthday: birthday,
            scanKeyDescriptor: descriptor,
            labelStates: [labelState]
        )

        #expect(metadata.walletBirthday.blockHeight == 800_000)
        #expect(metadata.walletBirthday.date == birthdayDate)
        #expect(metadata.scanKeyDescriptor.derivationPath == derivationPath)
        #expect(metadata.labelStates.first?.label == "Savings")
        #expect(metadata.labelStates.first?.nextIndex == 3)
    }

    @Test("backup metadata rejects invalid recovery anchors")
    func rejectInvalidRecoveryAnchors() {
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidBlockHeight(-1)) {
            _ = try OpalBase.ReusablePaymentAddress.WalletBirthday(blockHeight: -1)
        }
        #expect(throws: OpalBase.ReusablePaymentAddress.Error.invalidLabel("   ")) {
            _ = try OpalBase.ReusablePaymentAddress.LabelState(label: "   ", nextIndex: 0)
        }
    }
}
