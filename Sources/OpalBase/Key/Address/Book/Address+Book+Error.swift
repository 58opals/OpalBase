// Address+Book+Error.swift

import Foundation

extension Address.Book {
    enum Error: Swift.Error {
        case indexOutOfBounds
        
        case privateKeyNotFound
        case addressNotFound
        case entryNotFound
        
        case privateKeyDuplicated(PrivateKey)
        case addressDuplicated(Address)
        case entryDuplicated(Address.Book.Entry)
        
        case insufficientFunds
        
        case cacheInvalid
        case cacheUpdateFailed
    }
}
