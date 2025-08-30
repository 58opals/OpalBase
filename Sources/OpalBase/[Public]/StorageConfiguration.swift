// StorageConfiguration.swift

import Foundation

public struct StorageConfiguration: Sendable {
    public var appGroupContainer: URL?
    public var isMemoryOnly: Bool
    
    public init(appGroupContainer: URL? = nil, isMemoryOnly: Bool = false) {
        self.appGroupContainer = appGroupContainer
        self.isMemoryOnly = isMemoryOnly
    }
}
