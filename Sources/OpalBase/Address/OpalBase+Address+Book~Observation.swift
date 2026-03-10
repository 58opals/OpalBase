// OpalBase+Address+Book~Observation.swift

import Foundation

extension _OpalBase.Address.Book {
    func notifyNewEntry(_ entry: Entry) async {
        await entryPublisher.publish(entry)
    }
    
    func observeNewEntries() async -> AsyncStream<Entry> {
        await entryPublisher.observeEntries()
    }
}
