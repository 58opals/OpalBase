// OpalBase+Address+Book~Observation.swift

import Foundation

extension _OpalBase.Address.Book {
    func notifyNewEntry(_ entry: EntryModel) async {
        await entryPublisher.publish(entry)
    }
    
    func observeNewEntries() async -> AsyncStream<EntryModel> {
        await entryPublisher.observeEntries()
    }
}
