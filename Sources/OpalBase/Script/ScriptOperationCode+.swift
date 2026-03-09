// ScriptOperationCode+.swift

import Foundation

extension ScriptOperationCode {
    var data: Data { Data([self.rawValue]) }
}

