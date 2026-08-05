// OpalBase+ReusablePaymentAddress+RestorationState~Validation.swift

extension _OpalBase.ReusablePaymentAddress.RestorationState {
    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              revision > 0,
              profile == .cashCodeV1,
              prefixLength == .sixteenBits,
              expirationUnixTime == nil,
              OpalBase.ReusablePaymentAddress.KeyOrigin.isValid(
                  keyOrigin.scanKeyIdentifier
              ),
              OpalBase.ReusablePaymentAddress.KeyOrigin.isValid(
                  keyOrigin.spendKeyIdentifier
              ),
              restoreStartHeight <= nextUnscannedHeight
        else {
            throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
        }

        _ = try makeReusablePaymentAddress()

        var confirmedOutpoints = Set<OpalBase.Transaction.Outpoint>()
        for match in confirmedMatches {
            guard match.blockHeight >= restoreStartHeight,
                  match.blockHeight < nextUnscannedHeight,
                  confirmedOutpoints.insert(match.output.outpoint).inserted
            else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
            }
            try validate(match.output, derivation: match.derivation)
        }

        var mempoolOutpoints = Set<OpalBase.Transaction.Outpoint>()
        for match in mempoolMatches {
            guard !confirmedOutpoints.contains(match.output.outpoint),
                  mempoolOutpoints.insert(match.output.outpoint).inserted
            else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
            }
            try validate(match.output, derivation: match.derivation)
        }

        guard reorganizationHistory.count <= 64,
              Set(reorganizationHistory.map(\.eventIdentifier)).count
                == reorganizationHistory.count
        else {
            throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
        }
        for reorganization in reorganizationHistory {
            let expectedRollbackHeight = min(
                reorganization.previousNextUnscannedHeight,
                max(restoreStartHeight, reorganization.firstAffectedHeight)
            )
            guard !reorganization.eventIdentifier.isEmpty,
                  reorganization.eventIdentifier.utf8.count <= 1_024,
                  reorganization.rollbackHeight >= restoreStartHeight,
                  reorganization.rollbackHeight
                    <= reorganization.previousNextUnscannedHeight,
                  reorganization.rollbackHeight == expectedRollbackHeight
            else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
            }
        }
    }

    func requireBinding(
        address: OpalBase.ReusablePaymentAddress,
        keyOrigin expectedKeyOrigin: OpalBase.ReusablePaymentAddress.KeyOrigin,
        restoreStartHeight expectedRestoreStartHeight: UInt
    ) throws {
        try validate()
        let expectedExpirationUnixTime: UInt32? = switch address.expiration {
        case .never: nil
        case .unixTime(let value): value
        }
        guard profile == address.profile,
              network == address.network,
              prefixLength == address.prefixLength,
              expirationUnixTime == expectedExpirationUnixTime,
              scanPublicKeyData == address.scanPublicKey.compressedData,
              spendPublicKeyData == address.spendPublicKey.compressedData,
              keyOrigin == expectedKeyOrigin,
              restoreStartHeight == expectedRestoreStartHeight
        else {
            throw OpalBase.ReusablePaymentAddress.Error
                .persistentStateBindingMismatch
        }
    }

    func requireCapabilities(
        scanSigningKey: OpalBase.Key.SigningKey,
        spendSigningKey: OpalBase.Key.SigningKey
    ) throws {
        let address = try makeReusablePaymentAddress()
        guard scanSigningKey.publicKey == address.scanPublicKey else {
            throw OpalBase.ReusablePaymentAddress.Error.scanSigningKeyMismatch
        }
        guard spendSigningKey.publicKey == address.spendPublicKey else {
            throw OpalBase.ReusablePaymentAddress.Error.spendSigningKeyMismatch
        }

        for match in confirmedMatches {
            try requireDerivation(
                match.derivation,
                scanSigningKey: scanSigningKey,
                spendSigningKey: spendSigningKey
            )
        }
        for match in mempoolMatches {
            try requireDerivation(
                match.derivation,
                scanSigningKey: scanSigningKey,
                spendSigningKey: spendSigningKey
            )
        }
    }

    private func validate(
        _ output: OpalBase.ReusablePaymentAddress.MatchedOutput,
        derivation: OpalBase.ReusablePaymentAddress.DerivationContext
    ) throws {
        guard derivation.childIndex == CashCodeDerivation.childIndex,
              derivation.qualifyingInputIndex
                < UInt32(CashCodeQualifyingInput.maximumInputCount),
              output.lockingScript == CashCodeDerivation.makeLockingScript(
                  for: derivation.receivingPublicKey
              )
        else {
            throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
        }
        do {
            _ = try output.transactionOutput.encode()
        } catch {
            throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
        }
    }

    private func requireDerivation(
        _ derivation: OpalBase.ReusablePaymentAddress.DerivationContext,
        scanSigningKey: OpalBase.Key.SigningKey,
        spendSigningKey: OpalBase.Key.SigningKey
    ) throws {
        do {
            let sharedPointDigest = try CashCodeDerivation.makeSharedPointDigest(
                signingKey: scanSigningKey,
                publicKey: derivation.senderPublicKey
            )
            let signingKey = try CashCodeDerivation.deriveSigningKey(
                from: spendSigningKey,
                sharedPointDigest: sharedPointDigest,
                outpoint: derivation.senderOutpoint
            )
            guard signingKey.publicKey == derivation.receivingPublicKey else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
            }
        } catch let error as OpalBase.ReusablePaymentAddress.Error {
            throw error
        } catch {
            throw OpalBase.ReusablePaymentAddress.Error.invalidPersistentState
        }
    }
}
