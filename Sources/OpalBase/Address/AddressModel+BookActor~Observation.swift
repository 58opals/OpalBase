// AddressModel+BookActor~Observation.swift

import Foundation

extension AddressModel.BookActor {
    func notifyNewEntry(_ entry: EntryModel) async {
        await entryPublisher.publish(entry)
    }
    
    func observeNewEntries() async -> AsyncStream<EntryModel> {
        await entryPublisher.observeEntries()
    }
}
