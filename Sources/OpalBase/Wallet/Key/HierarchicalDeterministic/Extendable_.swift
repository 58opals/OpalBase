// Opal Base by 58 Opals

import Foundation

protocol Extendable {
    var precedent: (key: Data?, chainCode: Data?, fingerprint: Data?) { get }
    var chainCode: Data { get }
    var depth: UInt8 { get }
    
    func diverge(to index: DerivationPath.Index, depth: UInt8) -> Self
}
