// Storage+Value.swift

import Foundation
import SwiftData

extension Storage {
    @Model
    final class Value {
        @Attribute(.unique) var key: String
        @Attribute(.externalStorage) var payload: Data
        var updatedAt: Date
        
        init(key: String, payload: Data, updatedAt: Date) {
            self.key = key
            self.payload = payload
            self.updatedAt = updatedAt
        }
    }
}
