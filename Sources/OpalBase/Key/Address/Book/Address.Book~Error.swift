import Foundation

extension Address.Book {
    public enum Error: Swift.Error {
        case indexOutOfBounds
        
        case privateKeyNotFound
        case addressNotFound
        case entryNotFound
        
        case privateKeyDuplicated
        case addressDuplicated
        case entryDuplicated
        
        case insufficientFunds
        
        case cacheInvalid
        case cacheUpdateFailed
    }
}
