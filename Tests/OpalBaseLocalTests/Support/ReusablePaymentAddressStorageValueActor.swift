// ReusablePaymentAddressStorageValueActor.swift

import Foundation
@testable import OpalBase

actor ReusablePaymentAddressStorageValueActor {
    private var values: [String: Data] = .init()
    private var committedStoreFailureBeforeMutationCount = 0
    private var committedStoreFailureAfterMutationCount = 0

    func store(_ data: Data, for key: OpalBase.Storage.Key) throws {
        if key.rawValue.hasSuffix(".committed"),
           committedStoreFailureAfterMutationCount > 0 {
            committedStoreFailureAfterMutationCount -= 1
            values[key.rawValue] = Data(data)
            throw GenerationPersistenceError.simulatedFailure
        }
        if key.rawValue.hasSuffix(".committed"),
           committedStoreFailureBeforeMutationCount > 0 {
            committedStoreFailureBeforeMutationCount -= 1
            throw GenerationPersistenceError.simulatedFailure
        }
        values[key.rawValue] = Data(data)
    }

    func load(for key: OpalBase.Storage.Key) -> Data? {
        values[key.rawValue].map { Data($0) }
    }

    func remove(for key: OpalBase.Storage.Key) {
        values.removeValue(forKey: key.rawValue)
    }

    func removeAll() {
        values.removeAll()
    }

    func readValues() -> [String: Data] {
        values
    }

    func failNextCommittedStoreBeforeMutation() {
        committedStoreFailureBeforeMutationCount += 1
    }

    func failNextCommittedStoreAfterMutation() {
        committedStoreFailureAfterMutationCount += 1
    }

    func makeValueClient() -> OpalBase.Storage.ValueClient {
        .init(
            valueWriter: { data, key in
                try await self.store(data, for: key)
            },
            valueReader: { key in
                await self.load(for: key)
            },
            valueDeleter: { key in
                await self.remove(for: key)
            },
            allValuesDeleter: {
                await self.removeAll()
            }
        )
    }
}
