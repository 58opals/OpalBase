// OpalBase+Account+MosaicAttemptJournalCodec.swift

#if os(macOS)
import CryptoKit
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Authenticated, versioned serialization for one wallet-private Mosaic attempt journal.
    ///
    /// The caller owns key persistence and assigns a stable, non-secret wallet/journal scope.
    /// AES-GCM detects modification and cross-scope substitution, but cannot detect replay of
    /// an older valid snapshot without an independent app-owned monotonic anchor.
    struct MosaicAttemptJournalCodec: Sendable {
        struct Scope: Sendable, Equatable {
            let walletIdentifier: UUID
            let journalIdentifier: UUID

            init(walletIdentifier: UUID, journalIdentifier: UUID) {
                self.walletIdentifier = walletIdentifier
                self.journalIdentifier = journalIdentifier
            }

            fileprivate var encoded: Data {
                Data(
                    "\(walletIdentifier.uuidString.lowercased())/\(journalIdentifier.uuidString.lowercased())"
                        .utf8
                )
            }
        }

        enum Failure: Swift.Error, Sendable, Equatable {
            case invalidKeyMaterial
            case unsupportedVersion(UInt8)
            case malformedEnvelope
            case authenticationFailed
            case encodingFailed
            case decodingFailed
            case invalidRecord(index: Int)
            case invalidSnapshot
        }

        private static let magic = Data("OPMJRN01".utf8)
        private static let formatVersion: UInt8 = 1
        private static let keyDerivationDomain = Data(
            "OpalBase/MosaicAttemptJournal/key/v1".utf8
        )
        private static let authenticationDomain = Data(
            "OpalBase/MosaicAttemptJournal/snapshot/v1".utf8
        )
        private static let maximumEnvelopeByteCount = 8 * 1_024 * 1_024
        private static let maximumPlaintextByteCount = 8 * 1_024 * 1_024
        private static let maximumRecordCount = 64

        private let encryptionKey: SymmetricKey
        private let authenticatedContext: Data

        init(authenticationKey: SymmetricKey, scope: Scope) throws {
            guard authenticationKey.bitCount == 256 else {
                throw Failure.invalidKeyMaterial
            }
            encryptionKey = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: authenticationKey,
                salt: Self.keyDerivationDomain,
                info: scope.encoded,
                outputByteCount: 32
            )
            var context = Self.authenticationDomain
            context.append(Self.formatVersion)
            Self.appendLengthPrefixed(scope.encoded, to: &context)
            authenticatedContext = context
        }

        func seal(
            records: [MosaicAttemptJournal.Record]
        ) throws -> Data {
            guard records.count <= Self.maximumRecordCount else {
                throw Failure.invalidSnapshot
            }

            let encodedRecords: [RecordDTO]
            do {
                encodedRecords = try records.enumerated().map { index, record in
                    do {
                        return try RecordDTO(record)
                    } catch {
                        throw Failure.invalidRecord(index: index)
                    }
                }
            } catch let failure as Failure {
                throw failure
            } catch {
                throw Failure.encodingFailed
            }

            let plaintext: Data
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                plaintext = try encoder.encode(
                    SnapshotDTO(
                        revision: UInt64(records.count),
                        records: encodedRecords
                    )
                )
            } catch {
                throw Failure.encodingFailed
            }
            guard plaintext.count <= Self.maximumPlaintextByteCount else {
                throw Failure.invalidSnapshot
            }

            do {
                let sealed = try AES.GCM.seal(
                    plaintext,
                    using: encryptionKey,
                    authenticating: authenticatedContext
                )
                guard let combined = sealed.combined else {
                    throw Failure.encodingFailed
                }
                var envelope = Self.magic
                envelope.append(Self.formatVersion)
                envelope.append(combined)
                guard envelope.count <= Self.maximumEnvelopeByteCount else {
                    throw Failure.invalidSnapshot
                }
                return envelope
            } catch let failure as Failure {
                throw failure
            } catch {
                throw Failure.encodingFailed
            }
        }

        func open(
            _ envelope: Data
        ) throws -> [MosaicAttemptJournal.Record] {
            let minimumCombinedByteCount = 12 + 16
            guard envelope.count >= Self.magic.count + 1 + minimumCombinedByteCount,
                  envelope.count <= Self.maximumEnvelopeByteCount,
                  envelope.prefix(Self.magic.count) == Self.magic else {
                throw Failure.malformedEnvelope
            }
            let versionIndex = envelope.index(
                envelope.startIndex,
                offsetBy: Self.magic.count
            )
            let version = envelope[versionIndex]
            guard version == Self.formatVersion else {
                throw Failure.unsupportedVersion(version)
            }
            let combined = envelope[envelope.index(after: versionIndex)...]

            let plaintext: Data
            do {
                let sealed = try AES.GCM.SealedBox(combined: combined)
                plaintext = try AES.GCM.open(
                    sealed,
                    using: encryptionKey,
                    authenticating: authenticatedContext
                )
            } catch {
                throw Failure.authenticationFailed
            }
            guard plaintext.count <= Self.maximumPlaintextByteCount else {
                throw Failure.invalidSnapshot
            }

            let snapshot: SnapshotDTO
            do {
                snapshot = try JSONDecoder().decode(
                    SnapshotDTO.self,
                    from: plaintext
                )
            } catch {
                throw Failure.decodingFailed
            }
            guard snapshot.records.count <= Self.maximumRecordCount,
                  snapshot.revision == UInt64(snapshot.records.count) else {
                throw Failure.invalidSnapshot
            }

            return try snapshot.records.enumerated().map { index, record in
                do {
                    return try record.makeRecord()
                } catch {
                    throw Failure.invalidRecord(index: index)
                }
            }
        }

        private static func appendLengthPrefixed(
            _ data: Data,
            to destination: inout Data
        ) {
            let count = UInt32(data.count)
            destination.append(UInt8(truncatingIfNeeded: count >> 24))
            destination.append(UInt8(truncatingIfNeeded: count >> 16))
            destination.append(UInt8(truncatingIfNeeded: count >> 8))
            destination.append(UInt8(truncatingIfNeeded: count))
            destination.append(data)
        }
    }
}

private extension _OpalBase.Account.MosaicAttemptJournalCodec {
    static let maximumByteFieldCount = 1_024 * 1_024
    static let maximumCollectionCount = 512
    static let maximumTextByteCount = 4_096

    struct SnapshotDTO: Codable {
        let revision: UInt64
        let records: [RecordDTO]
    }

    struct ReferenceDTO: Codable {
        let identifier: String
        let generation: UInt64

        init(_ reference: OpalFusion.Host.MosaicReservationReference) {
            identifier = reference.identifier.uuidString.lowercased()
            generation = reference.generation
        }

        func makeValue() throws
            -> OpalFusion.Host.MosaicReservationReference {
            guard let identifier = UUID(uuidString: identifier) else {
                throw Failure.decodingFailed
            }
            return .init(identifier: identifier, generation: generation)
        }
    }

    struct ReservationRequestDTO: Codable {
        let attemptIdentifier: Data
        let networkGenesisHash: Data
        let roundIdentifier: Data
        let expirationBitPattern: UInt64
        let componentCount: UInt32
        let feeRateSatoshisPerByte: UInt64
        let minimumExcessFeeSatoshis: UInt64
        let maximumExcessFeeSatoshis: UInt64
        let requiredExcessFeeSatoshis: UInt64
        let transactionProfileIdentifier: String

        init(_ request: OpalFusion.Host.MosaicReservationRequest) throws {
            guard let componentCount = UInt32(exactly: request.componentCount) else {
                throw Failure.encodingFailed
            }
            attemptIdentifier = Data(request.attemptIdentifier)
            networkGenesisHash = Data(request.networkGenesisHash)
            roundIdentifier = Data(request.roundIdentifier)
            expirationBitPattern = request.expiresAt
                .timeIntervalSince1970.bitPattern
            self.componentCount = componentCount
            feeRateSatoshisPerByte = request.feeRateSatoshisPerByte
            minimumExcessFeeSatoshis = request.minimumExcessFeeSatoshis
            maximumExcessFeeSatoshis = request.maximumExcessFeeSatoshis
            requiredExcessFeeSatoshis = request.requiredExcessFeeSatoshis
            transactionProfileIdentifier = request.transactionProfileIdentifier
        }

        func makeValue() throws -> OpalFusion.Host.MosaicReservationRequest {
            let expiration = Double(bitPattern: expirationBitPattern)
            guard expiration.isFinite,
                  !attemptIdentifier.isEmpty,
                  attemptIdentifier.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumByteFieldCount,
                  transactionProfileIdentifier.utf8.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumTextByteCount else {
                throw Failure.decodingFailed
            }
            return try .init(
                attemptIdentifier: [UInt8](attemptIdentifier),
                networkGenesisHash: [UInt8](networkGenesisHash),
                roundIdentifier: [UInt8](roundIdentifier),
                expiresAt: Date(timeIntervalSince1970: expiration),
                componentCount: Int(componentCount),
                feeRateSatoshisPerByte: feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
                requiredExcessFeeSatoshis: requiredExcessFeeSatoshis,
                transactionProfileIdentifier: transactionProfileIdentifier
            )
        }
    }

    struct SelectedInputDTO: Codable {
        let transactionHash: Data
        let outputIndex: UInt32
        let amountSatoshis: UInt64
        let lockingScript: Data

        init(_ input: _OpalBase.Account.MosaicAttemptJournal.SelectedInput) {
            transactionHash = input.transactionHash
            outputIndex = input.outputIndex
            amountSatoshis = input.amountSatoshis
            lockingScript = input.lockingScript
        }

        func makeValue() throws
            -> _OpalBase.Account.MosaicAttemptJournal.SelectedInput {
            guard transactionHash.count
                    == OpalBase.Transaction.Hash.expectedByteCount,
                  amountSatoshis > 0,
                  !lockingScript.isEmpty,
                  lockingScript.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumByteFieldCount else {
                throw Failure.decodingFailed
            }
            return .init(
                transactionHash: transactionHash,
                outputIndex: outputIndex,
                amountSatoshis: amountSatoshis,
                lockingScript: lockingScript
            )
        }
    }

    struct ParticipantInputDTO: Codable {
        let transactionHash: Data
        let outputIndex: UInt32
        let amountSatoshis: UInt64
        let lockingScript: Data
        let publicKey: Data?

        init(_ input: OpalFusion.Host.ParticipantInput) {
            transactionHash = Data(input.outpointTransactionHashBytes)
            outputIndex = input.outpointIndex
            amountSatoshis = input.amountSatoshis
            lockingScript = Data(input.lockingScriptBytes)
            publicKey = input.publicKey.map(Data.init)
        }

        func makeValue() throws -> OpalFusion.Host.ParticipantInput {
            guard transactionHash.count == 32,
                  amountSatoshis > 0,
                  !lockingScript.isEmpty,
                  lockingScript.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumByteFieldCount,
                  (publicKey?.count ?? 0)
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumByteFieldCount else {
                throw Failure.decodingFailed
            }
            return .init(
                outpointTransactionHashBytes: [UInt8](transactionHash),
                outpointIndex: outputIndex,
                amountSatoshis: amountSatoshis,
                lockingScriptBytes: [UInt8](lockingScript),
                publicKey: publicKey.map { [UInt8]($0) }
            )
        }
    }

    struct ParticipantOutputDTO: Codable {
        let lockingScript: Data
        let amountSatoshis: UInt64

        init(_ output: OpalFusion.Host.ParticipantOutput) {
            lockingScript = Data(output.lockingScriptBytes)
            amountSatoshis = output.amountSatoshis
        }

        func makeValue() throws -> OpalFusion.Host.ParticipantOutput {
            guard amountSatoshis > 0,
                  !lockingScript.isEmpty,
                  lockingScript.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumByteFieldCount else {
                throw Failure.decodingFailed
            }
            return .init(
                lockingScriptBytes: [UInt8](lockingScript),
                amountSatoshis: amountSatoshis
            )
        }
    }

    struct ParticipantReservationDTO: Codable {
        let inputs: [ParticipantInputDTO]
        let outputs: [ParticipantOutputDTO]

        init(_ reservation: OpalFusion.Host.ParticipantReservation) {
            inputs = reservation.inputs.map(ParticipantInputDTO.init)
            outputs = reservation.outputs.map(ParticipantOutputDTO.init)
        }

        func makeValue() throws -> OpalFusion.Host.ParticipantReservation {
            guard !inputs.isEmpty,
                  !outputs.isEmpty,
                  inputs.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumCollectionCount,
                  outputs.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumCollectionCount else {
                throw Failure.decodingFailed
            }
            return .init(
                inputs: try inputs.map { try $0.makeValue() },
                outputs: try outputs.map { try $0.makeValue() }
            )
        }
    }

    struct ReservationLeaseDTO: Codable {
        let reference: ReferenceDTO
        let expirationBitPattern: UInt64
        let participantReservation: ParticipantReservationDTO

        init(_ lease: OpalFusion.Host.MosaicReservationLease) {
            reference = .init(lease.reference)
            expirationBitPattern = lease.expiresAt.timeIntervalSince1970.bitPattern
            participantReservation = .init(lease.participantReservation)
        }

        func makeValue() throws -> OpalFusion.Host.MosaicReservationLease {
            let expiration = Double(bitPattern: expirationBitPattern)
            guard expiration.isFinite else {
                throw Failure.decodingFailed
            }
            return try .init(
                reference: try reference.makeValue(),
                expiresAt: Date(timeIntervalSince1970: expiration),
                participantReservation: try participantReservation.makeValue()
            )
        }
    }

    struct TranscriptBindingDTO: Codable {
        let profileIdentifier: String
        let manifestDigest: Data
        let commitmentSetDigest: Data
        let componentSetDigest: Data
        let unsignedTransactionDigest: Data
        let transcriptRoot: Data

        init(_ binding: OpalFusion.Host.MosaicTranscriptBinding) {
            profileIdentifier = binding.profile.rawValue
            manifestDigest = Data(binding.manifestDigest)
            commitmentSetDigest = Data(binding.commitmentSetDigest)
            componentSetDigest = Data(binding.componentSetDigest)
            unsignedTransactionDigest = Data(binding.unsignedTransactionDigest)
            transcriptRoot = Data(binding.transcriptRoot)
        }

        func makeValue(
            unsignedTransactionBytes: [UInt8]
        ) throws -> OpalFusion.Host.MosaicTranscriptBinding {
            guard profileIdentifier.utf8.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumTextByteCount,
                  let profile = OpalFusion.Mosaic.Profile(
                    rawValue: profileIdentifier
                  ) else {
                throw Failure.decodingFailed
            }
            let binding = try OpalFusion.Host.MosaicTranscriptBinding(
                profile: profile,
                manifestDigest: [UInt8](manifestDigest),
                commitmentSetDigest: [UInt8](commitmentSetDigest),
                componentSetDigest: [UInt8](componentSetDigest),
                unsignedTransactionBytes: unsignedTransactionBytes,
                acknowledgedTranscriptRoot: [UInt8](transcriptRoot)
            )
            guard binding.unsignedTransactionDigest
                    == [UInt8](unsignedTransactionDigest) else {
                throw Failure.decodingFailed
            }
            return binding
        }
    }

    struct SigningRequestDTO: Codable {
        let reservationReference: ReferenceDTO
        let roundIdentifier: Data
        let transcriptBinding: TranscriptBindingDTO
        let unsignedTransaction: Data
        let spentInputs: [ParticipantInputDTO]
        let localInputIndices: [UInt32]
        let expectedLocalOutputs: [ParticipantOutputDTO]
        let feeRateSatoshisPerByte: UInt64
        let minimumExcessFeeSatoshis: UInt64
        let maximumExcessFeeSatoshis: UInt64
        let requiredExcessFeeSatoshis: UInt64
        let transactionProfileIdentifier: String

        init(_ request: OpalFusion.Host.MosaicTransactionSigningRequest) throws {
            let localInputIndices = try request.localInputIndices.map { index in
                guard let encoded = UInt32(exactly: index) else {
                    throw Failure.encodingFailed
                }
                return encoded
            }
            reservationReference = .init(request.reservationReference)
            roundIdentifier = Data(request.roundIdentifier)
            transcriptBinding = .init(request.transcriptBinding)
            unsignedTransaction = Data(request.unsignedTransactionBytes)
            spentInputs = request.spentInputs.map(ParticipantInputDTO.init)
            self.localInputIndices = localInputIndices
            expectedLocalOutputs = request.expectedLocalOutputs.map(
                ParticipantOutputDTO.init
            )
            feeRateSatoshisPerByte = request.feeRateSatoshisPerByte
            minimumExcessFeeSatoshis = request.minimumExcessFeeSatoshis
            maximumExcessFeeSatoshis = request.maximumExcessFeeSatoshis
            requiredExcessFeeSatoshis = request.requiredExcessFeeSatoshis
            transactionProfileIdentifier = request.transactionProfileIdentifier
        }

        func makeValue() throws
            -> OpalFusion.Host.MosaicTransactionSigningRequest {
            guard !unsignedTransaction.isEmpty,
                  unsignedTransaction.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumByteFieldCount,
                  spentInputs.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumCollectionCount,
                  localInputIndices.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumCollectionCount,
                  expectedLocalOutputs.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumCollectionCount,
                  transactionProfileIdentifier.utf8.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumTextByteCount else {
                throw Failure.decodingFailed
            }
            let transactionBytes = [UInt8](unsignedTransaction)
            return try .init(
                reservationReference: try reservationReference.makeValue(),
                roundIdentifier: [UInt8](roundIdentifier),
                transcriptBinding: try transcriptBinding.makeValue(
                    unsignedTransactionBytes: transactionBytes
                ),
                unsignedTransactionBytes: transactionBytes,
                spentInputs: try spentInputs.map { try $0.makeValue() },
                localInputIndices: localInputIndices.map(Int.init),
                expectedLocalOutputs: try expectedLocalOutputs.map {
                    try $0.makeValue()
                },
                feeRateSatoshisPerByte: feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
                requiredExcessFeeSatoshis: requiredExcessFeeSatoshis,
                transactionProfileIdentifier: transactionProfileIdentifier
            )
        }
    }

    struct RecordDTO: Codable {
        enum Kind: String, Codable {
            case reservationIntent
            case reserved
            case signingIntent
            case locallySigned
            case releaseIntent
            case released
            case commitIntent
            case committed
            case broadcastApproved
            case broadcastIntent
            case broadcastAccepted
        }

        let kind: Kind
        let reference: ReferenceDTO?
        let request: ReservationRequestDTO?
        let selectedInputs: [SelectedInputDTO]?
        let outputAmountsSatoshis: [UInt64]?
        let lease: ReservationLeaseDTO?
        let signingRequest: SigningRequestDTO?
        let finalizedTransaction: Data?
        let completeTransaction: Data?
        let transactionHash: Data?

        init(_ record: _OpalBase.Account.MosaicAttemptJournal.Record) throws {
            var kind: Kind
            var reference: ReferenceDTO?
            var request: ReservationRequestDTO?
            var selectedInputs: [SelectedInputDTO]?
            var outputAmountsSatoshis: [UInt64]?
            var lease: ReservationLeaseDTO?
            var signingRequest: SigningRequestDTO?
            var finalizedTransaction: Data?
            var completeTransaction: Data?
            var transactionHash: Data?

            switch record {
            case let .reservationIntent(
                valueReference,
                valueRequest,
                valueInputs,
                valueAmounts
            ):
                kind = .reservationIntent
                reference = .init(valueReference)
                request = try .init(valueRequest)
                selectedInputs = valueInputs.map(SelectedInputDTO.init)
                outputAmountsSatoshis = valueAmounts
            case let .reserved(value):
                kind = .reserved
                lease = .init(value)
            case let .signingIntent(value):
                kind = .signingIntent
                signingRequest = try .init(value)
            case let .locallySigned(valueReference, transaction):
                kind = .locallySigned
                reference = .init(valueReference)
                finalizedTransaction = Data(
                    transaction.signedFusionTransactionBytes
                )
            case let .releaseIntent(valueReference):
                kind = .releaseIntent
                reference = .init(valueReference)
            case let .released(valueReference):
                kind = .released
                reference = .init(valueReference)
            case let .commitIntent(valueReference, transaction):
                kind = .commitIntent
                reference = .init(valueReference)
                completeTransaction = Data(transaction.transactionBytes)
            case let .committed(valueReference, transaction):
                kind = .committed
                reference = .init(valueReference)
                completeTransaction = Data(transaction.transactionBytes)
            case let .broadcastApproved(valueReference, transaction):
                kind = .broadcastApproved
                reference = .init(valueReference)
                completeTransaction = Data(transaction.transactionBytes)
            case let .broadcastIntent(valueReference, transaction):
                kind = .broadcastIntent
                reference = .init(valueReference)
                completeTransaction = Data(transaction.transactionBytes)
            case let .broadcastAccepted(
                valueReference,
                transaction,
                hash
            ):
                kind = .broadcastAccepted
                reference = .init(valueReference)
                completeTransaction = Data(transaction.transactionBytes)
                transactionHash = hash.naturalOrder
            }

            self.kind = kind
            self.reference = reference
            self.request = request
            self.selectedInputs = selectedInputs
            self.outputAmountsSatoshis = outputAmountsSatoshis
            self.lease = lease
            self.signingRequest = signingRequest
            self.finalizedTransaction = finalizedTransaction
            self.completeTransaction = completeTransaction
            self.transactionHash = transactionHash
        }

        func makeRecord() throws
            -> _OpalBase.Account.MosaicAttemptJournal.Record {
            switch kind {
            case .reservationIntent:
                guard let reference,
                      let request,
                      let selectedInputs,
                      let outputAmountsSatoshis,
                      lease == nil,
                      signingRequest == nil,
                      finalizedTransaction == nil,
                      completeTransaction == nil,
                      transactionHash == nil,
                      !selectedInputs.isEmpty,
                      selectedInputs.count
                        <= _OpalBase.Account.MosaicAttemptJournalCodec
                            .maximumCollectionCount,
                      !outputAmountsSatoshis.isEmpty,
                      outputAmountsSatoshis.count
                        <= _OpalBase.Account.MosaicAttemptJournalCodec
                            .maximumCollectionCount,
                      outputAmountsSatoshis.allSatisfy({ $0 > 0 }) else {
                    throw Failure.decodingFailed
                }
                return .reservationIntent(
                    reference: try reference.makeValue(),
                    request: try request.makeValue(),
                    selectedInputs: try selectedInputs.map {
                        try $0.makeValue()
                    },
                    outputAmountsSatoshis: outputAmountsSatoshis
                )
            case .reserved:
                guard reference == nil,
                      request == nil,
                      selectedInputs == nil,
                      outputAmountsSatoshis == nil,
                      let lease,
                      signingRequest == nil,
                      finalizedTransaction == nil,
                      completeTransaction == nil,
                      transactionHash == nil else {
                    throw Failure.decodingFailed
                }
                return .reserved(try lease.makeValue())
            case .signingIntent:
                guard reference == nil,
                      request == nil,
                      selectedInputs == nil,
                      outputAmountsSatoshis == nil,
                      lease == nil,
                      let signingRequest,
                      finalizedTransaction == nil,
                      completeTransaction == nil,
                      transactionHash == nil else {
                    throw Failure.decodingFailed
                }
                return .signingIntent(try signingRequest.makeValue())
            case .locallySigned:
                guard let reference,
                      request == nil,
                      selectedInputs == nil,
                      outputAmountsSatoshis == nil,
                      lease == nil,
                      signingRequest == nil,
                      let finalizedTransaction,
                      finalizedTransaction.count
                        <= _OpalBase.Account.MosaicAttemptJournalCodec
                            .maximumByteFieldCount,
                      completeTransaction == nil,
                      transactionHash == nil else {
                    throw Failure.decodingFailed
                }
                return .locallySigned(
                    reference: try reference.makeValue(),
                    transaction: .init(
                        signedFusionTransactionBytes: [UInt8](
                            finalizedTransaction
                        )
                    )
                )
            case .releaseIntent:
                return try makeReferenceOnlyRecord(
                    constructor: _OpalBase.Account.MosaicAttemptJournal.Record
                        .releaseIntent
                )
            case .released:
                return try makeReferenceOnlyRecord(
                    constructor: _OpalBase.Account.MosaicAttemptJournal.Record
                        .released
                )
            case .commitIntent:
                return try makeCompleteTransactionRecord(
                    constructor: _OpalBase.Account.MosaicAttemptJournal.Record
                        .commitIntent
                )
            case .committed:
                return try makeCompleteTransactionRecord(
                    constructor: _OpalBase.Account.MosaicAttemptJournal.Record
                        .committed
                )
            case .broadcastApproved:
                return try makeCompleteTransactionRecord(
                    constructor: _OpalBase.Account.MosaicAttemptJournal.Record
                        .broadcastApproved
                )
            case .broadcastIntent:
                return try makeCompleteTransactionRecord(
                    constructor: _OpalBase.Account.MosaicAttemptJournal.Record
                        .broadcastIntent
                )
            case .broadcastAccepted:
                guard let reference,
                      request == nil,
                      selectedInputs == nil,
                      outputAmountsSatoshis == nil,
                      lease == nil,
                      signingRequest == nil,
                      finalizedTransaction == nil,
                      let completeTransaction,
                      !completeTransaction.isEmpty,
                      completeTransaction.count
                        <= _OpalBase.Account.MosaicAttemptJournalCodec
                            .maximumByteFieldCount,
                      let transactionHash,
                      transactionHash.count
                        == OpalBase.Transaction.Hash.expectedByteCount else {
                    throw Failure.decodingFailed
                }
                return .broadcastAccepted(
                    reference: try reference.makeValue(),
                    transaction: try .init(
                        transactionBytes: [UInt8](completeTransaction)
                    ),
                    transactionHash: .init(naturalOrder: transactionHash)
                )
            }
        }

        private func makeReferenceOnlyRecord(
            constructor: (
                OpalFusion.Host.MosaicReservationReference
            ) -> _OpalBase.Account.MosaicAttemptJournal.Record
        ) throws -> _OpalBase.Account.MosaicAttemptJournal.Record {
            guard let reference,
                  request == nil,
                  selectedInputs == nil,
                  outputAmountsSatoshis == nil,
                  lease == nil,
                  signingRequest == nil,
                  finalizedTransaction == nil,
                  completeTransaction == nil,
                  transactionHash == nil else {
                throw Failure.decodingFailed
            }
            return constructor(try reference.makeValue())
        }

        private func makeCompleteTransactionRecord(
            constructor: (
                OpalFusion.Host.MosaicReservationReference,
                OpalFusion.Host.MosaicCompleteTransaction
            ) -> _OpalBase.Account.MosaicAttemptJournal.Record
        ) throws -> _OpalBase.Account.MosaicAttemptJournal.Record {
            guard let reference,
                  request == nil,
                  selectedInputs == nil,
                  outputAmountsSatoshis == nil,
                  lease == nil,
                  signingRequest == nil,
                  finalizedTransaction == nil,
                  let completeTransaction,
                  !completeTransaction.isEmpty,
                  completeTransaction.count
                    <= _OpalBase.Account.MosaicAttemptJournalCodec
                        .maximumByteFieldCount,
                  transactionHash == nil else {
                throw Failure.decodingFailed
            }
            return constructor(
                try reference.makeValue(),
                try .init(transactionBytes: [UInt8](completeTransaction))
            )
        }
    }
}
#endif
