#if os(macOS)
// OpalBase+Account+CashFusionPreparation.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    public func prepareCashFusionSession(
        configuration: OpalBase.Account.CashFusionSession.Configuration,
        request: OpalBase.Account.CashFusionRequest
    ) async throws -> OpalBase.Account.CashFusionSession {
        try await prepareCashFusionSession(
            configuration: configuration,
            request: request,
            sessionFactory: Self.defaultCashFusionWrappedSessionFactory
        )
    }

    func prepareCashFusionSession(
        configuration: OpalBase.Account.CashFusionSession.Configuration,
        request: OpalBase.Account.CashFusionRequest,
        sessionFactory: CashFusionWrappedSessionFactory
    ) async throws -> OpalBase.Account.CashFusionSession {
        let reservation = try await prepareCashFusionReservation(request: request)
        let participantReservationSource = CashFusionParticipantReservationSource(
            reservation: reservation.participantReservation
        )
        let transactionAssembler = CashFusionTransactionAssembler(
            reservation: reservation
        )
        let observerSink = CashFusionObserverSink()
        let wrappedSession = await sessionFactory(
            configuration.makeClientConfiguration(),
            configuration.genesisHash,
            configuration.joinPools.makeJoinPools(),
            participantReservationSource,
            transactionAssembler,
            nil,
            observerSink
        )
        let session = CashFusionSession(
            reservation: reservation,
            wrappedSession: wrappedSession,
            observerSink: observerSink
        )
        await observerSink.bind(to: session)
        return session
    }

    func prepareCashFusionReservation(
        request: OpalBase.Account.CashFusionRequest
    ) async throws -> CashFusionReservation {
        guard request.selectedInputs.isEmpty == false else {
            throw Error.cashFusionHasNoSelectedInputs
        }
        guard request.outputAmounts.isEmpty == false else {
            throw Error.cashFusionHasNoOutputAmounts
        }
        guard Set(request.selectedInputs).count == request.selectedInputs.count else {
            throw Error.cashFusionUnsupportedSelectedInputs
        }

        let reservedInputs = try await resolveCashFusionReservedInputs(
            from: request.selectedInputs
        )

        do {
            try await addressBook.reserveUTXOs(
                Set(request.selectedInputs),
                tokenSelectionPolicy: .excludeTokenUTXOs
            )
        } catch {
            throw Error.cashFusionReservationFailed(error)
        }

        let reservedReceivingEntries: [OpalBase.Address.Book.Entry]
        do {
            reservedReceivingEntries = try await reserveCashFusionReceivingEntries(
                count: request.outputAmounts.count
            )
        } catch {
            await addressBook.releaseUTXOs(Set(request.selectedInputs))
            throw Error.cashFusionOutputReservationFailed(error)
        }

        let participantOutputs = zip(
            reservedReceivingEntries,
            request.outputAmounts
        ).map { entry, amount in
            OpalFusion.Host.ParticipantOutput(
                lockingScriptBytes: [UInt8](entry.address.lockingScript.data),
                amountSatoshis: amount.uint64
            )
        }

        return CashFusionReservation(
            addressBook: addressBook,
            reservedInputs: reservedInputs,
            reservedReceivingEntries: reservedReceivingEntries,
            participantReservation: .init(
                inputs: reservedInputs.map(\.participantInput),
                outputs: participantOutputs
            )
        )
    }

    private func resolveCashFusionReservedInputs(
        from selectedInputs: [OpalBase.Transaction.Output.Unspent]
    ) async throws -> [CashFusionReservation.ReservedInput] {
        let classifications = try await classifyCashFusionSelectedInputs(selectedInputs)
        var reservedInputs: [CashFusionReservation.ReservedInput] = []
        reservedInputs.reserveCapacity(classifications.count)

        for classification in classifications {
            switch classification.status {
            case .eligible(let reservedInput):
                reservedInputs.append(reservedInput)
            case .blocked(.tokenUTXO):
                throw Error.cashFusionCannotSpendTokenUTXOs
            case .blocked(.unsupportedLockingScript), .blocked(.noEligibleUTXOs):
                throw Error.cashFusionUnsupportedSelectedInputs
            }
        }

        return reservedInputs
    }

    func classifyCashFusionSelectedInputs(
        _ selectedInputs: [OpalBase.Transaction.Output.Unspent]
    ) async throws -> [CashFusionSelectedInputClassification] {
        var classifications: [CashFusionSelectedInputClassification] = []
        classifications.reserveCapacity(selectedInputs.count)

        for selectedInput in selectedInputs {
            let classification = try await classifyCashFusionSelectedInput(selectedInput)
            classifications.append(classification)
        }

        return classifications
    }

    private func classifyCashFusionSelectedInput(
        _ selectedInput: OpalBase.Transaction.Output.Unspent
    ) async throws -> CashFusionSelectedInputClassification {
        if selectedInput.tokenData != nil {
            return .init(
                unspentOutput: selectedInput,
                status: .blocked(.tokenUTXO)
            )
        }

        let script: OpalBase.Script
        do {
            script = try OpalBase.Script.decode(lockingScript: selectedInput.lockingScript)
        } catch {
            return .init(
                unspentOutput: selectedInput,
                status: .blocked(.unsupportedLockingScript)
            )
        }

        let publicKeyHash: OpalBase.Key.PublicKey.Hash
        switch script {
        case .p2pkh_OPCHECKSIG(let hash):
            publicKeyHash = hash
        default:
            return .init(
                unspentOutput: selectedInput,
                status: .blocked(.unsupportedLockingScript)
            )
        }

        let address: OpalBase.Address
        do {
            address = try OpalBase.Address(script: script)
        } catch {
            throw Error.cashFusionUnsupportedSelectedInputs
        }

        guard let entry = await addressBook.findEntry(for: address) else {
            throw Error.cashFusionUnsupportedSelectedInputs
        }

        let privateKey: Data
        do {
            privateKey = try await addressBook.generatePrivateKey(
                at: entry.derivationPath.index,
                for: entry.derivationPath.usage
            )
        } catch {
            throw Error.cashFusionReservationFailed(error)
        }

        let compressedPublicKey: Data
        do {
            let publicKey = try OpalBase.Key.PublicKey(privateKeyData: privateKey)
            let derivedPublicKeyHash = OpalBase.Key.PublicKey.Hash(publicKey: publicKey)
            guard derivedPublicKeyHash == publicKeyHash else {
                throw Error.cashFusionUnsupportedSelectedInputs
            }
            compressedPublicKey = publicKey.compressedData
        } catch let error as OpalBase.Account.Error {
            throw error
        } catch {
            throw Error.cashFusionReservationFailed(error)
        }

        let reservedInput = CashFusionReservation.ReservedInput(
            unspentOutput: selectedInput,
            privateKey: privateKey,
            compressedPublicKey: compressedPublicKey,
            participantInput: .init(
                outpointTransactionHashBytes: [UInt8](selectedInput.previousTransactionHash.reverseOrder),
                outpointIndex: selectedInput.previousTransactionOutputIndex,
                amountSatoshis: selectedInput.value,
                lockingScriptBytes: [UInt8](selectedInput.lockingScript),
                publicKey: [UInt8](compressedPublicKey)
            )
        )

        return .init(
            unspentOutput: selectedInput,
            status: .eligible(reservedInput)
        )
    }

    private func reserveCashFusionReceivingEntries(
        count: Int
    ) async throws -> [OpalBase.Address.Book.Entry] {
        var reservedEntries: [OpalBase.Address.Book.Entry] = []
        reservedEntries.reserveCapacity(count)

        do {
            for _ in 0..<count {
                let reservedEntry = try await addressBook.reserveNextEntry(for: .receiving)
                reservedEntries.append(reservedEntry)
            }
        } catch {
            try await releaseCashFusionReceivingEntries(
                reservedEntries,
                shouldKeepUsed: false
            )
            throw error
        }

        return reservedEntries
    }

    private func releaseCashFusionReceivingEntries(
        _ entries: [OpalBase.Address.Book.Entry],
        shouldKeepUsed: Bool
    ) async throws {
        var firstError: Swift.Error?

        for entry in entries {
            do {
                _ = try await addressBook.releaseReservation(
                    address: entry.address,
                    shouldKeepUsed: shouldKeepUsed
                )
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }
}

private extension _OpalBase.Account.CashFusionSession.Configuration {
    func makeClientConfiguration() -> OpalFusion.Client.Configuration {
        .init(
            coordinatorHost: coordinator.host,
            coordinatorPort: coordinator.port,
            coordinatorRequiresTLS: coordinator.requiresTLS,
            covertChannel: covertChannel.makeCovertChannelConfiguration(),
            torSocks5: torSocks5?.makeTorSocks5Configuration()
        )
    }
}

private extension _OpalBase.Account.CashFusionSession.Configuration.CovertChannel {
    func makeCovertChannelConfiguration() -> OpalFusion.Transport.CovertChannelConfiguration {
        .init(
            entryPath: entryPath,
            maxPayloadBytes: maxPayloadBytes,
            requestTimeoutMilliseconds: requestTimeoutMilliseconds
        )
    }
}

private extension _OpalBase.Account.CashFusionSession.Configuration.TorSocks5 {
    func makeTorSocks5Configuration() -> OpalFusion.Transport.TorSocks5Configuration {
        .init(
            host: host,
            port: port,
            resolvesCoordinatorHostNameRemotely: resolvesCoordinatorHostNameRemotely
        )
    }
}

private extension _OpalBase.Account.CashFusionSession.Configuration.JoinPools {
    func makeJoinPools() -> OpalFusion.ProtocolModel.JoinPools {
        .init(
            tiers: tiers,
            tags: tags.map(\.makePoolTag)
        )
    }
}

private extension _OpalBase.Account.CashFusionSession.Configuration.PoolTag {
    var makePoolTag: OpalFusion.ProtocolModel.PoolTag {
        .init(
            identifier: identifier,
            limit: limit,
            noIp: noIp
        )
    }
}
#endif
