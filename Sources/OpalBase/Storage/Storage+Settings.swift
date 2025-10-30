// Storage+Settings.swift

import Foundation

extension Storage {
    public actor Settings {
        public struct Configuration: Sendable {
            public var directory: URL?
            public var filename: String
            public var isMemoryOnly: Bool
            
            public init(directory: URL? = nil,
                        filename: String = "opal-settings.json",
                        isMemoryOnly: Bool = false) {
                self.directory = directory
                self.filename = filename
                self.isMemoryOnly = isMemoryOnly
            }
        }
        
        public enum Error: Swift.Error, Sendable {
            case directoryCreationFailed(URL, Swift.Error)
            case dataReadFailed(URL, Swift.Error)
            case dataWriteFailed(URL, Swift.Error)
            case initializationFailed(Swift.Error)
        }
        
        struct Snapshot: Codable, Sendable {
            var feePreferences: [UInt32: Wallet.FeePolicy.Preference] = .init()
        }
        
        private let fileURL: URL?
        private var snapshot: Snapshot
        private let initializationFailure: Swift.Error?
        
        public init(configuration: Configuration = .init()) {
            var resolvedFileURL: URL?
            var workingSnapshot: Snapshot = .init()
            var storedFailure: Swift.Error?
            
            if configuration.isMemoryOnly {
                resolvedFileURL = nil
                workingSnapshot = .init()
            } else {
                let directory: URL
                if let configuredDirectory = configuration.directory {
                    directory = configuredDirectory
                } else if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    directory = applicationSupport
                } else {
                    directory = FileManager.default.temporaryDirectory
                }
                
                if storedFailure == nil {
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    } catch {
                        storedFailure = Error.directoryCreationFailed(directory, error)
                    }
                }
                
                if storedFailure == nil {
                    let candidateURL = directory.appendingPathComponent(configuration.filename)
                    resolvedFileURL = candidateURL
                    
                    if FileManager.default.fileExists(atPath: candidateURL.path) {
                        do {
                            let data = try Data(contentsOf: candidateURL)
                            workingSnapshot = try JSONDecoder().decode(Snapshot.self, from: data)
                        } catch {
                            storedFailure = Error.dataReadFailed(candidateURL, error)
                            workingSnapshot = .init()
                        }
                    } else {
                        workingSnapshot = .init()
                        do {
                            try Storage.Settings.persist(workingSnapshot, to: candidateURL)
                        } catch {
                            storedFailure = Error.dataWriteFailed(candidateURL, error)
                        }
                    }
                }
            }
            
            self.fileURL = resolvedFileURL
            self.snapshot = workingSnapshot
            self.initializationFailure = storedFailure
        }
        
        public func loadFeePreference(for accountIndex: UInt32) throws -> Wallet.FeePolicy.Preference? {
            try ensureInitialized()
            return snapshot.feePreferences[accountIndex]
        }
        
        public func updateFeePreference(_ preference: Wallet.FeePolicy.Preference, for accountIndex: UInt32) throws {
            try ensureInitialized()
            snapshot.feePreferences[accountIndex] = preference
            try persistSnapshotIfNeeded()
        }
        
        public func removeFeePreference(for accountIndex: UInt32) throws {
            try ensureInitialized()
            snapshot.feePreferences.removeValue(forKey: accountIndex)
            try persistSnapshotIfNeeded()
        }
        
        public func loadAllFeePreferences() throws -> [UInt32: Wallet.FeePolicy.Preference] {
            try ensureInitialized()
            return snapshot.feePreferences
        }
    }
}

private extension Storage.Settings {
    func ensureInitialized() throws {
        if let initializationFailure {
            throw Error.initializationFailed(initializationFailure)
        }
    }
    
    func persistSnapshotIfNeeded() throws {
        guard let fileURL else { return }
        do {
            try Storage.Settings.persist(snapshot, to: fileURL)
        } catch {
            throw Error.dataWriteFailed(fileURL, error)
        }
    }
    
    static func persist(_ snapshot: Snapshot, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}
