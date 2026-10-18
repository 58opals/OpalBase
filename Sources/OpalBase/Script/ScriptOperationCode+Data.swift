// ScriptOperationCode+Data.swift

import Foundation

extension ScriptOperationCode {
    package var data: Data { Data([self.rawValue]) }
}
