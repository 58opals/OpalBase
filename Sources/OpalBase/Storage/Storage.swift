// Storage.swift

import Foundation
import SwiftData

public actor Storage {
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    let security: Security
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    
    public init(
        modelConfiguration: ModelConfiguration? = nil,
        securityOptions: Security.Options = .init()
    ) throws {
        self.security = Security(options: securityOptions)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        
        if let modelConfiguration {
            self.modelContainer = try ModelContainer(for: Storage.Value.self,
                                                     configurations: modelConfiguration)
        } else {
            self.modelContainer = try ModelContainer(for: Storage.Value.self)
        }
        self.modelContext = ModelContext(self.modelContainer)
    }
}

extension Storage {
    public enum Error: Swift.Error {
        case swiftDataUnavailable
        case swiftDataFailure(Swift.Error)
        case encodingFailure(Swift.Error)
        case decodingFailure(Swift.Error)
        case secureStoreFailure(Swift.Error)
        case missingAccountIdentifier(UInt32)
    }
}
