// Storage.swift

import Foundation

public actor Storage {
    
}

extension Storage {
    public enum Error: Swift.Error {
        case directoryCreationFailed(URL, Swift.Error)
        case dataReadFailed(URL, Swift.Error)
        case dataWriteFailed(URL, Swift.Error)
        case secureStoreUnavailable
        case secureStoreFailure(Swift.Error)
    }
}
